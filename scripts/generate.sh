#!/bin/bash
# Generate gRPC Swift client from proto files.
# Requires: protoc, swift-protobuf (protoc-gen-swift), grpc-swift (protoc-gen-grpc-swift)
#
# Install plugins:
#   brew install protobuf protoc-gen-grpc-swift
#   # protoc-gen-swift: build from swift-protobuf or use SPM plugin
#
# Or build plugins from source:
#   git clone --recurse-submodules https://github.com/apple/swift-protobuf.git
#   swift build -c release --product protoc-gen-swift
#   git clone https://github.com/grpc/grpc-swift.git && cd grpc-swift
#   swift build -c release --product protoc-gen-grpc-swift

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_DIR="$ROOT_DIR/proto"
OUT_DIR="$ROOT_DIR/Sources/NoxySDK/Generated"

# Try to find plugins
PROTOC_GEN_SWIFT="${PROTOC_GEN_SWIFT:-$(command -v protoc-gen-swift 2>/dev/null)}"
PROTOC_GEN_GRPC_SWIFT="${PROTOC_GEN_GRPC_SWIFT:-$(command -v protoc-gen-grpc-swift 2>/dev/null)}"

if [ -z "$PROTOC_GEN_SWIFT" ] || [ ! -x "$PROTOC_GEN_SWIFT" ]; then
  echo "Error: protoc-gen-swift not found. Set PROTOC_GEN_SWIFT or install via swift-protobuf."
  exit 1
fi
if [ -z "$PROTOC_GEN_GRPC_SWIFT" ] || [ ! -x "$PROTOC_GEN_GRPC_SWIFT" ]; then
  echo "Error: protoc-gen-grpc-swift not found. Set PROTOC_GEN_GRPC_SWIFT or install via brew."
  exit 1
fi

mkdir -p "$OUT_DIR"
protoc \
  --proto_path="$PROTO_DIR" \
  --swift_out="$OUT_DIR" \
  --grpc-swift_out="$OUT_DIR" \
  --plugin=protoc-gen-swift="$PROTOC_GEN_SWIFT" \
  --plugin=protoc-gen-grpc-swift="$PROTOC_GEN_GRPC_SWIFT" \
  "$PROTO_DIR"/noxy.device.proto

echo "Generated Swift code in $OUT_DIR"
