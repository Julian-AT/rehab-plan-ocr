# Model registry

Runtime lockfiles under `runtime/` pin normal application assets. Experimental model
cards retain training/deployment identities and their original evaluation results.
They do not change the application's selected model.

`app_evaluations` adds later observations through the native simulator app, with
the raw private report and its SHA-256. Earlier desktop results remain separate:
prompt routing, rejection and strict output decoding can change the counts. The
scope field distinguishes interpretation from complete recognition/import. Neither
scope establishes the complete spoken workflow or physical-device performance.

All current custom models remain unqualified. Synthetic development counts,
runtime compatibility and warm-session reuse cannot replace reviewed references,
independent evaluation, human listening or the final release gates. Additional
evaluation metadata does not rewrite the older report's registry identity; its
original card content remains recoverable from Git.
