"""Check training storage headroom without loading arrays or changing run evidence."""

import json
import math
import shutil

GIB = 1024**3


def tensor_bytes(value):
    """Count nested MLX/Paddle/NumPy tensor metadata without materializing values."""
    if isinstance(value, dict):
        return sum(tensor_bytes(item) for item in value.values())
    if isinstance(value, (list, tuple)):
        return sum(tensor_bytes(item) for item in value)
    if hasattr(value, "nbytes"):
        count = value.nbytes
    elif hasattr(value, "element_size") and hasattr(value, "shape"):
        count = math.prod(value.shape) * value.element_size()
    elif value is None or isinstance(value, (bool, int, float, str)):
        return 0  # Optimizer scheduler/scalar metadata is covered by the fixed allowance.
    else:
        raise ValueError(f"Unsupported checkpoint state type: {type(value).__name__}")
    if type(count) is not int or count < 0:
        raise ValueError("Checkpoint tensor byte counts must be nonnegative integers")
    return count


def checkpoint_peak(model, optimizer, *, trainable=None, random=None):
    """Allow two copies, Adam moments not yet allocated, and serialization metadata."""
    parameters = tensor_bytes(model if trainable is None else trainable)
    # Two float32 moments can occupy four times the bytes of float16 parameters.
    optimizer_bytes = max(tensor_bytes(optimizer), 4 * parameters)
    return 2 * (tensor_bytes(model) + optimizer_bytes + tensor_bytes(random)) + 64 * 1024**2


def require_storage(root, directory, planned_peak_gib, checkpoint_peak_bytes=0):
    reserve = json.loads((root / "config/storage/retention.json").read_text())["reserve_gib"]
    if type(reserve) not in {int, float} or not math.isfinite(reserve) or reserve < 20:
        raise ValueError("Training storage policy requires at least 20 GiB reserve")
    if (
        type(planned_peak_gib) not in {int, float}
        or not math.isfinite(planned_peak_gib)
        or planned_peak_gib < 0
        or type(checkpoint_peak_bytes) is not int
        or checkpoint_peak_bytes < 0
    ):
        raise ValueError("Training storage peak must be finite and nonnegative")
    peak = max(math.ceil(planned_peak_gib * GIB), checkpoint_peak_bytes)
    free = shutil.disk_usage(directory).free
    if free < math.ceil(reserve * GIB) + peak:
        raise RuntimeError(
            f"Training paused: {free / GIB:.2f} GiB free; need {reserve:g} GiB reserve "
            f"+ {peak / GIB:.2f} GiB checkpoint/temporary peak; completed checkpoints retained"
        )
    return {"free_bytes": free, "reserve_gib": reserve, "peak_bytes": peak}
