"""Copy FP32 inference BatchNorms into explicit Paddle-grouped ONNX division."""

import copy
import hashlib

PREFIX = "batchnorm_division/"


def lower_batchnorm(model):
    """Preserve original parameters, non-BN nodes and public tensor identities."""
    import numpy as np
    import onnx

    if [(item.domain, item.version) for item in model.opset_import] != [("", 17)]:
        raise ValueError("Expected original opset 17")
    if model.functions or model.graph.sparse_initializer:
        raise ValueError("Only the retained flat dense inference graph is supported")
    names = {
        value.name
        for value in [
            *model.graph.input,
            *model.graph.output,
            *model.graph.initializer,
            *model.graph.value_info,
        ]
    }
    names.update(
        value for node in model.graph.node for value in [node.name, *node.input, *node.output]
    )
    if any(name.startswith(PREFIX) for name in names):
        raise ValueError("Candidate namespace already exists")
    inferred = onnx.shape_inference.infer_shapes(model, strict_mode=True)
    types = {
        value.name: value.type.tensor_type
        for value in [*inferred.graph.input, *inferred.graph.value_info, *inferred.graph.output]
    }
    constants = {value.name: value for value in model.graph.initializer}
    for node in model.graph.node:
        if node.op_type == "Constant" and node.domain == "":
            attributes = {value.name: value for value in node.attribute}
            value = attributes.get("value")
            if (
                len(node.output) == 1
                and value is not None
                and value.type == onnx.AttributeProto.TENSOR
            ):
                if node.output[0] in constants:
                    raise ValueError("Duplicate parameter identity")
                constants[node.output[0]] = value.t
    result = copy.deepcopy(model)
    del result.graph.node[:]
    replacements = []
    for node in model.graph.node:
        if node.op_type != "BatchNormalization":
            result.graph.node.append(node)
            continue
        attrs = {a.name: onnx.helper.get_attribute_value(a) for a in node.attribute}
        if (
            node.domain
            or len(node.input) != 5
            or len(node.output) != 1
            or attrs.get("training_mode", 0) != 0
            or set(attrs) - {"epsilon", "momentum", "training_mode"}
        ):
            raise ValueError("Only a single-output inference BatchNorm is supported")
        tensor_type = types.get(node.input[0])
        if (
            tensor_type is None
            or tensor_type.elem_type != onnx.TensorProto.FLOAT
            or len(tensor_type.shape.dim) != 4
        ):
            raise ValueError("Expected a known FP32 NCHW rank-four operand")
        parameters = []
        for name in node.input[1:]:
            if name not in constants:
                raise ValueError("BatchNorm parameter must be an unchanged constant")
            value = onnx.numpy_helper.to_array(constants[name])
            if (
                value.dtype != np.float32
                or value.ndim != 1
                or value.size == 0
                or not np.isfinite(value).all()
            ):
                raise ValueError("Expected finite FP32 channel parameters")
            parameters.append(value)
        channels = parameters[0].size
        if any(value.size != channels for value in parameters):
            raise ValueError("BatchNorm parameter channel counts disagree")
        declared_channels = tensor_type.shape.dim[1].dim_value
        if declared_channels and declared_channels != channels:
            raise ValueError("Operand and parameter channel counts disagree")
        epsilon = np.asarray(attrs.get("epsilon", 1e-5), dtype=np.float32)
        with np.errstate(over="ignore", invalid="ignore"):
            denominator = parameters[3] + epsilon
        if (
            not np.isfinite(epsilon)
            or epsilon < 0
            or (parameters[3] < 0).any()
            or not np.isfinite(denominator).all()
            or not (denominator > 0).all()
        ):
            raise ValueError("Expected nonnegative epsilon/variance and positive denominator")
        base = PREFIX + str(len(replacements)) + "/"
        for name, value in [
            ("epsilon", epsilon),
            ("one", np.asarray(1, dtype=np.float32)),
            ("shape", np.asarray([1, -1, 1, 1], dtype=np.int64)),
        ]:
            result.graph.initializer.append(onnx.numpy_helper.from_array(value, base + name))

        def op(kind, inputs, name, *, output=None):
            target = output or base + name
            result.graph.node.append(
                onnx.helper.make_node(kind, inputs, [target], name=base + name)
            )
            return target

        operand, scale, bias, mean, variance = node.input
        stddev = op("Sqrt", [op("Add", [variance, base + "epsilon"], "variance")], "stddev")
        inverse = op("Div", [base + "one", stddev], "inverse")
        adjusted_scale = op("Mul", [inverse, scale], "adjusted_scale")
        offset = op("Mul", [op("Mul", [mean, inverse], "mean_inverse"), scale], "offset")
        adjusted_bias = op("Sub", [bias, offset], "adjusted_bias")
        scale4 = op("Reshape", [adjusted_scale, base + "shape"], "scale4")
        bias4 = op("Reshape", [adjusted_bias, base + "shape"], "bias4")
        op("Add", [op("Mul", [operand, scale4], "scaled"), bias4], "output", output=node.output[0])
        replacements.append(
            {
                "output": node.output[0],
                "channels": int(channels),
                "epsilon_bytes": epsilon.tobytes().hex(),
                "original_node_sha256": hashlib.sha256(node.SerializeToString()).hexdigest(),
                "parameter_sha256": [
                    hashlib.sha256(value.tobytes()).hexdigest() for value in parameters
                ],
            }
        )
    if not replacements:
        raise ValueError("No inference BatchNorm to transform")
    retained = [
        node.SerializeToString() for node in result.graph.node if not node.name.startswith(PREFIX)
    ]
    expected = [
        node.SerializeToString()
        for node in model.graph.node
        if node.op_type != "BatchNormalization"
    ]
    if retained != expected or list(
        result.graph.initializer[: len(model.graph.initializer)]
    ) != list(model.graph.initializer):
        raise ValueError("Unrelated original nodes or constants changed")
    onnx.checker.check_model(result)
    return result, replacements
