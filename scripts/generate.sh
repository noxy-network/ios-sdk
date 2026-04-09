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

if [ -z "$PROTOC_GEN_SWIFT" ] || [ ! -x "$PROTOC_GEN_SWIFT" ]; then
  echo "Error: protoc-gen-swift not found. Set PROTOC_GEN_SWIFT or: brew install swift-protobuf"
  exit 1
fi

mkdir -p "$OUT_DIR"
# Only regenerate pb.swift (grpc-swift 2.x plugin output is incompatible with grpc-swift 1.x in Package.swift).
# Keep noxy.device.grpc.swift in sync manually when RPC surface changes, or use protoc-gen-grpc-swift from grpc-swift 1.x.
protoc \
  --proto_path="$PROTO_DIR" \
  --swift_out="$OUT_DIR" \
  --plugin=protoc-gen-swift="$PROTOC_GEN_SWIFT" \
  "$PROTO_DIR"/noxy.device.proto

echo "Generated noxy.device.pb.swift in $OUT_DIR"
