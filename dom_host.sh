#!/bin/bash -eu

export GROUP="${GROUP:-}"
export QUEUE="${QUEUE:-}"
export AFTER="${AFTER:-}"
export USE_CUDA="${USE_CUDA:-1}"
export PROFILE="${PROFILE:-0}"
export DEBUG="${DEBUG:-0}"
export RANKS_PER_NODE=1
export RESERVED_CORES="${RESERVED_CORES:-4}"
export DEBUG_COPYING=0

export EXECUTABLE="$SOLEIL_DIR"/src/dom_host.exec
export MINUTES=10
export NUM_RANKS=1

source "$SOLEIL_DIR"/src/run.sh
