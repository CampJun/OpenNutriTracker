# Label reading lets a model transcribe nutrition numbers

In this fork a vision model (DeepSeek `deepseek-flash`) reads nutrition labels into Custom Foods, an exception to upstream's rule that a model never supplies a nutrition number (`docs/ai-architecture.md`). Transcribing a printed number is not estimating one: on seven real label photos vision read 99% of fields correctly and invented no values, against 83% for on-device OCR with a parser. The exception is bounded: the model only copies amounts printed on the label, never derives one from a %DV, every value passes through a review screen with arithmetic checks (%DV, Atwater, sub-totals), and meal logging keeps the original rule and schema unchanged.

## Considered Options

Measured on the same seven photos, three runs each (prototype on branch `proto/label-ocr`):

- On-device OCR (ML Kit) with a deterministic parser: 83%, the only option that produced a wrong value the checks did not flag, and brittle on rotated, bilingual and old-format labels. Rejected.
- The model reading OCR text instead of the photo: 97%, keeps the photo on the device, but spent about seven times the tokens and was less consistent between runs. Rejected.
- On-device OCR as a fallback when the model cannot be reached: rejected. Typing the values from the label is always correct and avoids maintaining a second parser.
