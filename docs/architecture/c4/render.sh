#!/usr/bin/env bash
# Renders every C4 diagram in this directory to png/<name>.png.
#
# Renderers, in order of preference:
#   1. PLANTUML_JAR=/path/to/plantuml.jar (run with java)
#   2. `plantuml` on PATH
#   3. the plantuml/plantuml Docker image
# The C4 library ships inside PlantUML (<C4/...> includes), so rendering works
# offline. Distro packages can bundle a C4 library too old for these diagrams
# (Ubuntu's 1.2020.2 lacks C4_Dynamic, C4_Deployment, tags and ContainerQueue),
# so each local renderer is probed before use and skipped if it fails.
set -euo pipefail

cd "$(dirname "$0")"

DOCKER_IMAGE="plantuml/plantuml:1.2025.2"
JAR_URL="https://github.com/plantuml/plantuml/releases/download/v1.2025.2/plantuml-1.2025.2.jar"

# Uses the newest C4 features the diagrams depend on.
probe_diagram() {
  cat <<'EOF'
@startuml
!include <C4/C4_Container>
!include <C4/C4_Dynamic>
!include <C4/C4_Deployment>
LAYOUT_TOP_DOWN()
AddElementTag("planned", $borderStyle=DashedLine())
AddRelTag("planned", $lineStyle=DashedLine())
ContainerQueue(q, "q", "t")
SHOW_LEGEND()
@enduml
EOF
}

supports_c4() {
  probe_diagram | "$@" -pipe -tpng >/dev/null 2>&1
}

plantuml_cmd=()

if [[ -n "${PLANTUML_JAR:-}" ]]; then
  if [[ ! -f "$PLANTUML_JAR" ]]; then
    echo "render.sh: PLANTUML_JAR=$PLANTUML_JAR does not exist" >&2
    exit 1
  fi
  if ! supports_c4 java -jar "$PLANTUML_JAR"; then
    echo "render.sh: $PLANTUML_JAR cannot render the C4 macros these diagrams use; use a newer jar ($JAR_URL)" >&2
    exit 1
  fi
  plantuml_cmd=(java -jar "$PLANTUML_JAR")
elif command -v plantuml >/dev/null 2>&1 && supports_c4 plantuml; then
  plantuml_cmd=(plantuml)
elif command -v docker >/dev/null 2>&1; then
  plantuml_cmd=(docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/work" -w /work "$DOCKER_IMAGE")
else
  if command -v plantuml >/dev/null 2>&1; then
    echo "render.sh: $(plantuml -version 2>&1 | head -1) bundles a C4 library too old for these diagrams." >&2
  else
    echo "render.sh: no PlantUML renderer found." >&2
  fi
  cat >&2 <<EOF
Install a current jar (needs java and graphviz) and point PLANTUML_JAR at it:
  curl -sSL -o ~/.local/share/plantuml/plantuml.jar --create-dirs $JAR_URL
  PLANTUML_JAR=~/.local/share/plantuml/plantuml.jar $0
or install docker to use $DOCKER_IMAGE.
EOF
  exit 1
fi

mkdir -p png
echo "render.sh: rendering with ${plantuml_cmd[*]}"
"${plantuml_cmd[@]}" -tpng -o png ./*.puml
ls -1 png
