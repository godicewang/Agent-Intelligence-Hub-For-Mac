# TraceLab Adapter

TraceLab is the primary future dataset for large-scale FrostReplayBench validation. Keep raw downloads under `datasets/tracelab/`, which is git-ignored.

Fetch the fixed v0.0.1 JSONL artifact:

```bash
Scripts/fetch_tracelab_dataset.sh
```

The script verifies the official SHA256 from the v0.0.1 release before leaving the dataset in place.
