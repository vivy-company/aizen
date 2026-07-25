#!/usr/bin/env bash
set -euo pipefail

schema_path="${1:-Packages/Wire/Sources/AizenWire/Protocol/aizen_wire_v1.proto}"

if [[ ! -f "$schema_path" ]]; then
  echo "Missing protobuf schema: $schema_path" >&2
  exit 1
fi

if ! command -v protoc >/dev/null 2>&1; then
  echo "protoc is required to validate $schema_path" >&2
  exit 1
fi

protoc --descriptor_set_out=/dev/null --proto_path="$(dirname "$schema_path")" "$schema_path"

awk '
  /^message[[:space:]]+/ {
    message = $2
    sub(/[[:space:]]*\{.*/, "", message)
    delete numbers
    next
  }
  /^[[:space:]]*}/ { message = ""; next }
  message != "" && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*[0-9]+;/ {
    split($0, parts, "=")
    number = parts[2]
    sub(/;.*/, "", number)
    gsub(/[[:space:]]/, "", number)
    if (numbers[number] != "") {
      printf "Duplicate protobuf field number %s in message %s: %s and %s\\n", number, message, numbers[number], $0 > "/dev/stderr"
      exit 1
    }
    numbers[number] = $0
  }
' "$schema_path"
