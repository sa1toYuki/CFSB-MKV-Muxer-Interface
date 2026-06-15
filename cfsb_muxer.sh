#!/usr/bin/env bash

set -euo pipefail

# ─── Constantes ───────────────────────────────────────────────────────────────
readonly SCRIPT_NAME="$(basename "$0")"
TAG="${TAG:-CFSB}"

# ─── Cores & Estilos ──────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_CYAN='\033[36m'
    C_GREEN='\033[32m'
    C_YELLOW='\033[33m'
    C_RED='\033[31m'
    C_MAGENTA='\033[35m'
    C_BLUE='\033[34m'
else
    C_RESET='' C_BOLD='' C_DIM='' C_CYAN='' C_GREEN=''
    C_YELLOW='' C_RED='' C_MAGENTA='' C_BLUE=''
fi

# ─── UI ───────────────────────────────────────────────────────────────────────
die() {
    printf '%b\n' "${C_RED}${C_BOLD}  ✖  $*${C_RESET}" >&2
    exit 1
}

info()    { printf '%b\n' "${C_CYAN}  ℹ  ${C_RESET}${C_BOLD}$*${C_RESET}"; }
success() { printf '%b\n' "${C_GREEN}  ✔  ${C_RESET}${C_BOLD}$*${C_RESET}"; }
warn()    { printf '%b\n' "${C_YELLOW}  ⚠  ${C_RESET}$*"; }
step()    { printf '%b\n' "${C_MAGENTA}  ▶  ${C_RESET}${C_BOLD}$*${C_RESET}"; }
detail()  { printf '%b\n' "${C_DIM}       $*${C_RESET}"; }

sep() {
    printf '%b\n' "${C_DIM}  ────────────────────────────────────────────────${C_RESET}"
}

header() {
    printf '\n'
    printf '%b\n' "${C_BLUE}${C_BOLD}  ╔══════════════════════════════════════════════╗${C_RESET}"
    printf '%b\n' "${C_BLUE}${C_BOLD}  ║   🎌  Crystal FanSub MKV Muxer               ║${C_RESET}"
    printf '%b\n' "${C_BLUE}${C_BOLD}  ╚══════════════════════════════════════════════╝${C_RESET}"
    printf '\n'
}

# ─── Spinner ──────────────────────────────────────────────────────────────────
# Uso: spinner OUT_VAR "label" cmd [args...]
#      spinner _ "label" cmd [args...]
spinner() {
    local _out_var="$1"; local label="$2"; shift 2
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    local tmp_out tmp_err
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    "$@" >"$tmp_out" 2>"$tmp_err" &
    local pid=$!

    tput civis 2>/dev/null || true

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%b' "${C_CYAN}  ${frames[$i]}  ${C_RESET}${C_BOLD}${label}${C_RESET}   "
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.08
    done

    wait "$pid"
    local exit_code=$?

    tput cnorm 2>/dev/null || true
    printf '\r'

    if [[ $exit_code -eq 0 ]]; then
        printf '%b\n' "${C_GREEN}  ✔  ${C_RESET}${C_BOLD}${label}${C_RESET}"
    else
        printf '%b\n' "${C_RED}  ✖  ${C_RESET}${C_BOLD}${label} falhou${C_RESET}"
        cat "$tmp_err" >&2
        rm -f "$tmp_out" "$tmp_err"
        exit "$exit_code"
    fi

    if [[ "$_out_var" != "_" ]]; then
        printf -v "$_out_var" '%s' "$(cat "$tmp_out")"
    fi
    rm -f "$tmp_out" "$tmp_err"
}

# ─── Verificações de dependências ─────────────────────────────────────────────
check_deps() {
    local missing=()

    for cmd in mkvmerge mkvinfo ffmpeg; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if ! command -v crc32 &>/dev/null && ! command -v cfv &>/dev/null; then
        missing+=("crc32 ou cfv")
    fi

    (( ${#missing[@]} == 0 )) || die "Dependências faltando: ${missing[*]}"
}

# ─── Detecção de faixas ───────────────────────────────────────────────────────
detect_video_codec() {
    local info
    info=$(mkvmerge --identify "$1" | grep -i "video" || true)

    if [[ "$info" == *"HEVC"* || "$info" == *"H.265"* ]]; then echo "HEVC"
    elif [[ "$info" == *"AVC"* || "$info" == *"H.264"* ]]; then echo "AVC"
    elif [[ "$info" == *"AV1"* ]]; then echo "AV1"
    else
        warn "Codec de vídeo desconhecido, assumindo HEVC"
        echo "HEVC"
    fi
}

detect_audio_codec() {
    local info
    info=$(mkvmerge --identify "$1" | grep -i "audio" | head -n 1 || true)

    if [[ "$info" == *"AAC"* ]];    then echo "AAC"
    elif [[ "$info" == *"FLAC"* ]]; then echo "FLAC"
    elif [[ "$info" == *"Opus"* ]]; then echo "Opus"
    else
        warn "Codec de áudio desconhecido, assumindo AAC"
        echo "AAC"
    fi
}

detect_resolution() {
    local json
    json=$(mkvmerge -J "$1")

    local altura
    altura=$(printf '%s' "$json" | grep -oP '"display_dimensions":\s*"\d+x\K\d+' | head -n 1)

    if [[ -z "$altura" ]]; then
        altura=$(printf '%s' "$json" | grep -oP '"pixel_dimensions":\s*"\d+x\K\d+' | head -n 1)
    fi

    echo "${altura:-1080}p"
}

# ─── Cálculo de CRC-32 ────────────────────────────────────────────────────────
calc_crc32() {
    local file="$1"
    local hash

    if command -v crc32 &>/dev/null; then
        hash=$(crc32 "$file")
    else
        hash=$(cfv -g "$file" | tail -n 1 | awk '{print $NF}')
    fi

    echo "${hash^^}"
}

_calc_crc_wrapper() {
    calc_crc32 "$1"
}

# ─── Coleta de entrada do usuário ─────────────────────────────────────────────
prompt_user() {
    printf '\n'
    printf '%b\n' "${C_BOLD}  📝  Informações do episódio${C_RESET}"
    sep
    printf '  %b 🎬%b Nome do Anime      : ' "$C_CYAN" "$C_RESET"; read -r ANIME
    printf '  %b 📺%b Número do Episódio : ' "$C_CYAN" "$C_RESET"; read -r EPISODIO
    printf '  %b 💿%b Source             : ' "$C_CYAN" "$C_RESET"; read -r SOURCE
    sep
    printf '\n'

    [[ -n "$ANIME" ]]    || die "Nome do anime não pode ser vazio."
    [[ -n "$EPISODIO" ]] || die "Número do episódio não pode ser vazio."
    [[ -n "$SOURCE" ]]   || die "Source não pode ser vazio."
}

# ─── Principal ────────────────────────────────────────────────────────────────
main() {
    header

    [[ $# -ge 1 ]] || die "Uso: $SCRIPT_NAME /caminho/da/pasta [pasta2 ...]"

    for pasta in "$@"; do
        process_pasta "$pasta"
        [[ $# -gt 1 ]] && sep
    done
}

process_pasta() {
    local pasta="$1"
    [[ -d "$pasta" ]] || die "Pasta não encontrada: $pasta"

    step "Verificando dependências..."
    check_deps
    success "Dependências OK"

    sep

    local mkv_original legenda capitulos

    local mkv_count
    mkv_count=$(find "$pasta" -maxdepth 1 -type f -name "*.mkv" | wc -l)
    mkv_original=$(find "$pasta" -maxdepth 1 -type f -name "*.mkv" | sort | head -n 1)
    (( mkv_count > 1 )) && warn "Múltiplos MKVs encontrados, usando: $(basename "$mkv_original")"

    local ass_count
    ass_count=$(find "$pasta" -maxdepth 1 -type f -name "*.ass" | wc -l)
    legenda=$(find "$pasta" -maxdepth 1 -type f -name "*.ass" | sort | head -n 1)
    (( ass_count > 1 )) && warn "Múltiplos ASS encontrados, usando: $(basename "$legenda")"

    local txt_count
    txt_count=$(find "$pasta" -maxdepth 1 -type f -name "*.txt" | wc -l)
    capitulos=$(find "$pasta" -maxdepth 1 -type f -name "*.txt" | sort | head -n 1)
    (( txt_count > 1 )) && warn "Múltiplos TXT encontrados, usando: $(basename "$capitulos")"

    [[ -n "$mkv_original" ]] || die "Nenhum arquivo .mkv encontrado em: $pasta"
    [[ -n "$legenda" ]]      || die "Nenhum arquivo .ass encontrado em: $pasta"
    [[ -n "$capitulos" ]]    || die "Nenhum arquivo .txt encontrado em: $pasta"

    info "Arquivos de origem detectados"
    detail "🎞  $(basename "$mkv_original")"
    detail "💬  $(basename "$legenda")"
    detail "📖  $(basename "$capitulos")"

    prompt_user

    local tempo_inicial=$SECONDS

    step "Analisando faixas de mídia..."

    local video_codec audio_codec qualidade
    video_codec=$(detect_video_codec "$mkv_original")
    audio_codec=$(detect_audio_codec "$mkv_original")
    qualidade=$(detect_resolution "$mkv_original")

    success "Análise concluída"
    detail "🎥  Vídeo    : ${C_BOLD}${video_codec}${C_RESET}"
    detail "🔊  Áudio    : ${C_BOLD}${audio_codec}${C_RESET}"
    detail "📐  Resolução: ${C_BOLD}${qualidade}${C_RESET}"
    printf '\n'

    local nome_base mkv_temp mkv_final
    nome_base="[$TAG] ${ANIME} - ${EPISODIO} [${qualidade}][${SOURCE}][${video_codec}][${audio_codec}]"
    mkv_temp="${pasta}/${nome_base}_TEMP.mkv"

    [[ -e "$mkv_temp" ]] && rm -f "$mkv_temp"

    trap '[[ -f "${mkv_temp:-}" ]] && rm -f "$mkv_temp"' EXIT INT TERM

    spinner _ "Multiplexando faixas..." \
        mkvmerge \
            --ui-language pt_BR \
            --priority lower \
            --output "$mkv_temp" \
            --no-subtitles \
            --language 1:ja-JP \
            --track-name '1:Japonês' \
            --original-flag 1:yes \
            '(' "$mkv_original" ')' \
            --language 0:pt-BR \
            --track-name '0:Português do Brasil' \
            '(' "$legenda" ')' \
            --chapters "$capitulos" \
            --generate-chapters-name-template 'Capítulo <NUM:2>' \
            --track-order 0:0,0:1,1:0

    local hash
    spinner hash "Calculando CRC-32..." _calc_crc_wrapper "$mkv_temp"

    mkv_final="${pasta}/${nome_base}[${hash}].mkv"
    mv -- "$mkv_temp" "$mkv_final"

    trap '[[ -f "${mkv_final:-}" ]] && rm -f "$mkv_final"' EXIT INT TERM

    local thumb="${pasta}/${nome_base}[${hash}].webp"
    spinner _ "Gerando thumbnail..." \
        ffmpeg -i "$mkv_final" -ss 00:02:00 -vf "thumbnail=300,setsar=1" -vframes 1 "$thumb" -y

    trap - EXIT INT TERM

    local duracao=$(( SECONDS - tempo_inicial ))
    printf '\n'
    printf '%b\n' "${C_GREEN}${C_BOLD}  ╔══════════════════════════════════════════════╗${C_RESET}"
    printf '%b\n' "${C_GREEN}${C_BOLD}  ║   ✅  Episódio gerado com sucesso!           ║${C_RESET}"
    printf '%b\n' "${C_GREEN}${C_BOLD}  ╚══════════════════════════════════════════════╝${C_RESET}"
    printf '\n'
    detail "🎬  $(basename "$mkv_final")"
    detail "🌅  $(basename "$thumb")"
    detail "🕐  Tempo: $(( duracao / 60 ))m $(( duracao % 60 ))s"
    printf '\n'
}

main "$@"
