#!/usr/bin/env bash
#
# pick-model — choose a local Ollama model and open OpenCode against it.
#
# Runs entirely inside the bubblewrap sandbox built by
# overlays/pkgs/ai/llm-sandboxed.nix, so the model server, the downloaded
# weights and the agent all see only $(pwd) plus their own state dirs.
#
# Starts `ollama serve` on a non-default port if it is not already up, and
# stops it again on exit — but only if this invocation is what started it.
set -euo pipefail

OLLAMA_PORT="${OLLAMA_PORT:-11435}"
OLLAMA_HOST="127.0.0.1:${OLLAMA_PORT}"
export OLLAMA_HOST
export OLLAMA_MODELS="${OLLAMA_MODELS:-$HOME/.local/share/ollama_project_models}"
# gfx1100 override — the Framework 16 / Ryzen 7040 iGPU is not in ROCm's
# supported list, so it has to masquerade as a supported target. Override for
# other hardware: HSA_OVERRIDE_GFX_VERSION=10.3.0 pick-model
export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.0.0}"
export OPENCODE_OLLAMA_API_BASE="http://${OLLAMA_HOST}"

LOG_DIR="${HOME}/.local/state/ollama"
LOG_FILE="${LOG_DIR}/serve.log"
mkdir -p "$OLLAMA_MODELS" "$LOG_DIR"

started_server=0
server_pid=""

# shellcheck disable=SC2329 # invoked via trap
cleanup() {
	if [ "${started_server}" = "1" ] && [ -n "${server_pid}" ]; then
		if kill -0 "${server_pid}" 2>/dev/null; then
			echo "Stopping ollama serve (pid ${server_pid})..."
			kill "${server_pid}"
			for _ in $(seq 1 15); do
				if ! kill -0 "${server_pid}" 2>/dev/null; then
					break
				fi
				sleep 1
			done
			if kill -0 "${server_pid}" 2>/dev/null; then
				echo "Forcing ollama serve shutdown..."
				kill -9 "${server_pid}" 2>/dev/null || true
			fi
		fi
	fi
}
trap 'cleanup' EXIT INT TERM

CATALOG=(
	"qwen2.5-coder:14b|Qwen 2.5 Coder 14B (Optimized for coding)"
	"qwen2.5-coder:32b|Qwen 2.5 Coder 32B (Complex logic & tasks)"
	"deepseek-r1:14b|DeepSeek-R1 Distilled Qwen 14B (Fast Reasoning)"
	"deepseek-r1:70b|DeepSeek-R1 Distilled Llama 70B (High Intelligence)"
	"llama3.3:70b|Llama-3.3-70B (Flagship Generalist)"
	"phi4:14b|Microsoft Phi-4 14B (Compact & Fast)"
)

if ! curl -sf "http://${OLLAMA_HOST}/api/version" >/dev/null 2>&1; then
	echo "Starting ollama serve on ${OLLAMA_HOST} (will be stopped on exit)..."
	ollama serve >"$LOG_FILE" 2>&1 </dev/null &
	server_pid=$!
	started_server=1
	for _ in $(seq 1 60); do
		if curl -sf "http://${OLLAMA_HOST}/api/version" >/dev/null 2>&1; then
			break
		fi
		if ! kill -0 "${server_pid}" 2>/dev/null; then
			echo "Failed to start ollama serve. See ${LOG_FILE}"
			exit 1
		fi
		sleep 1
	done
	if ! curl -sf "http://${OLLAMA_HOST}/api/version" >/dev/null 2>&1; then
		echo "Timed out waiting for ollama serve. See ${LOG_FILE}"
		exit 1
	fi
else
	echo "Reusing already-running ollama on ${OLLAMA_HOST} (left running on exit)."
fi

local_models=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' || true)

menu_options=()
for entry in "${CATALOG[@]}"; do
	model="${entry%%|*}"
	desc="${entry#*|}"
	if printf '%s\n' "$local_models" | grep -qxF "$model"; then
		menu_options+=("💾 [Downloaded] ${model} - ${desc}")
	else
		menu_options+=("🌐 [Available]  ${model} - ${desc}")
	fi
done

echo "========================================================="
echo "   Select a Model to Boot (Use arrow keys + Enter)"
echo "========================================================="

if ! choice=$(printf '%s\n' "${menu_options[@]}" | gum choose --header "Status | Model ID | Description"); then
	echo "Selection canceled."
	exit 1
fi

selected_model=$(awk '{print $3}' <<<"$choice")
selected_desc=$(awk -F' - ' '{print $2}' <<<"$choice")

echo "---------------------------------------------------------"
echo "Selected: ${selected_model}"

if ! printf '%s\n' "$local_models" | grep -qxF "$selected_model"; then
	echo "Model not present locally. Downloading into ${OLLAMA_MODELS}..."
	ollama pull "$selected_model"
fi

# Generate the OpenCode provider config in the project directory. Never
# clobber an existing one silently — it may be a hand-written config that is
# checked into the repo.
new_config="$(mktemp)"
trap 'rm -f "${new_config}"' RETURN 2>/dev/null || true
cat >"$new_config" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "ollama/${selected_model}",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": {
        "baseURL": "http://${OLLAMA_HOST}/v1"
      },
      "models": {
        "${selected_model}": {
          "name": "${selected_desc}"
        }
      }
    }
  }
}
EOF

if [ -f opencode.json ] && ! cmp -s opencode.json "$new_config"; then
	backup="opencode.json.bak"
	cp opencode.json "$backup"
	echo "Existing opencode.json differed — saved a copy as ${backup}"
fi
mv "$new_config" opencode.json

echo "Spawning OpenCode TUI connected to: ${selected_model}"
set +e
opencode
code=$?
set -e
echo "OpenCode closed."
exit "${code}"
