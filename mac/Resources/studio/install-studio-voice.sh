#!/bin/bash
# Installs Sparrow's optional Studio voice (OmniVoice by k2-fsa, Apache-2.0) on this Mac.
# Everything goes into ~/Library/Application Support/Sparrow/studio — delete that folder to remove it.
set -euo pipefail
SRC="${1:-}"          # a local OmniVoice folder (optional); otherwise it comes from PyPI
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/Library/Application Support/Sparrow/studio"
mkdir -p "$DIR/bin"
cd "$DIR"
echo "🐦  Installing Sparrow Studio voice (OmniVoice). This downloads about 4 GB and takes a while — keep this window open."
echo

ARCH="$(uname -m)"
PLAT=$([ "$ARCH" = "arm64" ] && echo osx-arm64 || echo osx-64)
if [ ! -x bin/micromamba ]; then
  echo "• Getting a private Python (micromamba)…"
  curl -fsSL "https://micro.mamba.pm/api/micromamba/$PLAT/latest" | tar -xj -C "$DIR" bin/micromamba
fi
export MAMBA_ROOT_PREFIX="$DIR/mamba"

if [ ! -x env/bin/python ]; then
  echo "• Creating the Python environment…"
  if [ "$ARCH" = "arm64" ]; then
    bin/micromamba create -y -q -p "$DIR/env" -c conda-forge python=3.11 pip
    env/bin/pip install -q torch torchaudio
  else
    # PyTorch no longer ships Intel-Mac wheels; conda-forge still builds them.
    bin/micromamba create -y -q -p "$DIR/env" -c conda-forge python=3.11 pip "pytorch-cpu>=2.4" "torchaudio>=2.4" numpy soundfile
  fi
fi

echo "• Installing OmniVoice…"
env/bin/pip install -q "transformers>=5.3.0" accelerate soundfile pydub numpy huggingface_hub
if [ -n "$SRC" ] && [ -f "$SRC/pyproject.toml" ]; then
  env/bin/pip install -q --no-deps "$SRC"
else
  env/bin/pip install -q --no-deps omnivoice
fi
cp "$HERE/sparrow_studio.py" "$DIR/sparrow_studio.py"

echo "• Downloading the voice model (about 3.3 GB)…"
env/bin/python - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download("k2-fsa/OmniVoice")
PY

echo "• Checking it works…"
env/bin/python -c "import omnivoice, torch; print('OmniVoice', omnivoice.__version__, '· torch', torch.__version__)"
date > "$DIR/installed"
echo
echo "✅  Studio voice is installed. Go back to Sparrow — it starts using it in a minute."
echo "    (You can close this window.)"
