"""Keep the rendered chat template byte-identical at the desktop CLI boundary."""


def arguments(path):
    # llama-completion -f removes one final LF; its default escape processing
    # also rewrites literal backslashes inside JSON/context. Neither is part of
    # the MLX or native C-API prompt contract.
    return ["--binary-file", str(path), "--no-escape"]
