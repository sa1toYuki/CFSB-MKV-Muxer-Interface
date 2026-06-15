#!/usr/bin/env bash

set -euo pipefail

# ─── Constantes ───────────────────────────────────────────────────────────────
readonly SCRIPT_NAME="$(basename "$0")"
readonly TAG="CFSB"

# ─── Cores & Estilos ──────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    readonly C_RESET='\033[0m'
    readonly C_BOLD='\033[1m'
    readonly C_DIM='\033[2m'
    readonly C_CYAN='\033[36m'
    readonly C_GREEN='\033[32m'
    readonly C_YELLOW='\033[33m'
    readonly C_RED='\033[31m'
    readonly C_MAGENTA='\033[35m'
    readonly C_BLUE='\033[34m'
else
    readonly C_RESET='' C_BOLD='' C_DIM='' C_CYAN='' C_GREEN=''
    readonly C_YELLOW='' C_RED='' C_MAGENTA='' C_BLUE=''
fi

# ─── UI ───────────────────────────────────────────────────────────────────────
die() {
    echo -e "${C_RED}${C_BOLD}  ✖  $*${C_RESET}" >&2
    exit 1
}

info()    { echo -e "${C_CYAN}  ℹ  ${C_RESET}${C_BOLD}$*${C_RESET}"; }
success() { echo -e "${C_GREEN}  ✔  ${C_RESET}${C_BOLD}$*${C_RESET}"; }
warn()    { echo -e "${C_YELLOW}  ⚠  ${C_RESET}$*"; }
step()    { echo -e "${C_MAGENTA}  ▶  ${C_RESET}${C_BOLD}$*${C_RESET}"; }
detail()  { echo -e "${C_DIM}       $*${C_RESET}"; }

sep() {
    echo -e "${C_DIM}  ────────────────────────────────────────────────${C_RESET}"
}

header() {
    echo
    echo -e "${C_BLUE}${C_BOLD}  ╔══════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BLUE}${C_BOLD}  ║   🎌  Crystal FanSub MKV Muxer               ║${C_RESET}"
    echo -e "${C_BLUE}${C_BOLD}  ╚══════════════════════════════════════════════╝${C_RESET}"
    echo
}

spinner() {
    local label="$1"; shift
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    local tmp_out tmp_err
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    "$@" >"$tmp_out" 2>"$tmp_err" &
    local pid=$!

    tput civis 2>/dev/null || true

    while kill -0 "$pid" 2>/dev/null; do
        echo -ne "\r${C_CYAN}  ${frames[$i]}  ${C_RESET}${C_BOLD}${label}${C_RESET}   "
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.08
    done || true

    wait "$pid"
    local exit_code=$?

    tput cnorm 2>/dev/null || true
    echo -ne "\r"

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${C_GREEN}  ✔  ${C_RESET}${C_BOLD}${label}${C_RESET}"
    else
        echo -e "${C_RED}  ✖  ${C_RESET}${C_BOLD}${label} falhou${C_RESET}"
        cat "$tmp_err" >&2
        rm -f "$tmp_out" "$tmp_err"
        exit "$exit_code"
    fi

    _SPINNER_OUT=$(cat "$tmp_out")
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
detect_codecs_and_resolution() {
    local file="$1"
    local identify_out json_out

    identify_out=$(mkvmerge --identify "$file")
    json_out=$(mkvmerge -J "$file")

    local video_info audio_info
    video_info=$(echo "$identify_out" | grep -i "video" || true)
    audio_info=$(echo "$identify_out" | grep -i "audio" | head -n 1 || true)

    if [[ "$video_info" == *"HEVC"* || "$video_info" == *"H.265"* ]]; then _DETECT_VIDEO="HEVC"
    elif [[ "$video_info" == *"AVC"* || "$video_info" == *"H.264"* ]]; then _DETECT_VIDEO="AVC"
    elif [[ "$video_info" == *"AV1"* ]]; then _DETECT_VIDEO="AV1"
    else _DETECT_VIDEO="HEVC"
    fi

    if [[ "$audio_info" == *"AAC"* ]];    then _DETECT_AUDIO="AAC"
    elif [[ "$audio_info" == *"FLAC"* ]]; then _DETECT_AUDIO="FLAC"
    elif [[ "$audio_info" == *"Opus"* ]]; then _DETECT_AUDIO="Opus"
    else _DETECT_AUDIO="AAC"
    fi

    local altura
    altura=$(echo "$json_out" | grep -oP '"display_dimensions":\s*"\d+x\K\d+' | head -n 1)
    [[ -z "$altura" ]] && altura=$(echo "$json_out" | grep -oP '"pixel_dimensions":\s*"\d+x\K\d+' | head -n 1)
    _DETECT_RES="${altura:-1080}p"
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

# ─── Coleta de entrada do usuário ─────────────────────────────────────────────
prompt_user() {
    echo
    echo -e "${C_BOLD}  📝  Informações do episódio${C_RESET}"
    sep
    echo -ne "  ${C_CYAN}🎬${C_RESET} Nome do Anime      : "; read -r ANIME
    echo -ne "  ${C_CYAN}📺${C_RESET} Número do Episódio : "; read -r EPISODIO
    echo -ne "  ${C_CYAN}💿${C_RESET} Source             : "; read -r SOURCE
    sep
    echo

    [[ -n "$ANIME" ]]    || die "Nome do anime não pode ser vazio."
    [[ -n "$EPISODIO" ]] || die "Número do episódio não pode ser vazio."
    [[ -n "$SOURCE" ]]   || die "Source não pode ser vazio."
}

# ─── Principal ────────────────────────────────────────────────────────────────
main() {
    header

    [[ $# -eq 1 ]] || die "Uso: $SCRIPT_NAME /caminho/da/pasta"

    local pasta="$1"
    [[ -d "$pasta" ]] || die "Pasta não encontrada: $pasta"

    step "Verificando dependências..."
    check_deps
    success "Dependências OK"

    sep

    # Localiza arquivos de entrada
    local mkv_original legenda capitulos

    local -a mkvs
    mapfile -t mkvs < <(find "$pasta" -maxdepth 1 -type f -name "*.mkv" | sort)
    (( ${#mkvs[@]} == 1 )) || die "Esperado 1 arquivo .mkv, encontrado ${#mkvs[@]} em: $pasta"
    mkv_original="${mkvs[0]}"

    legenda=$(find "$pasta" -maxdepth 1 -type f -name "*.ass" | sort | head -n 1)
    capitulos=$(find "$pasta" -maxdepth 1 -type f -name "*.txt" | sort | head -n 1)

    [[ -n "$legenda" ]]   || die "Nenhum arquivo .ass encontrado em: $pasta"
    [[ -n "$capitulos" ]] || die "Nenhum arquivo .txt encontrado em: $pasta"

    info "Arquivo de origem detectado"
    detail "🎞  $(basename "$mkv_original")"
    detail "💬  $(basename "$legenda")"
    detail "📖  $(basename "$capitulos")"

    prompt_user

    local tempo_inicial=$SECONDS

    # ── Detecta codecs e resolução ──
    step "Analisando faixas de mídia..."

    detect_codecs_and_resolution "$mkv_original"
    local video_codec="$_DETECT_VIDEO"
    local audio_codec="$_DETECT_AUDIO"
    local qualidade="$_DETECT_RES"

    success "Análise concluída"
    detail "🎥  Vídeo  : ${C_BOLD}${video_codec}${C_RESET}"
    detail "🔊  Áudio  : ${C_BOLD}${audio_codec}${C_RESET}"
    detail "📐  Resolução: ${C_BOLD}${qualidade}${C_RESET}"
    echo

    # ── Monta nomes ──
    local nome_base mkv_temp mkv_final
    nome_base="[$TAG] ${ANIME} - ${EPISODIO} [${qualidade}][${SOURCE}][${video_codec}][${audio_codec}]"
    mkv_temp="${pasta}/${nome_base}_TEMP.mkv"

    rm -f "$mkv_temp"

    # ── Muxing com spinner ──
    spinner "Multiplexando faixas..." \
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

    # ── CRC-32 ──
    step "Calculando CRC-32..."
    local hash
    hash=$(calc_crc32 "$mkv_temp")
    success "CRC-32: $hash"

    mkv_final="${pasta}/${nome_base}[${hash}].mkv"
    mv -- "$mkv_temp" "$mkv_final"

    # ── Thumbnail ──
    local thumb="${pasta}/${nome_base}[${hash}].webp"
    spinner "Gerando thumbnail..." \
        ffmpeg -i "$mkv_final" -ss 00:01:00 -vf "thumbnail=10,setsar=1" -vframes 1 "$thumb" -y

    # ── Resumo final ──
    local duracao
    duracao=$(( SECONDS - tempo_inicial ))
    echo
    echo -e "${C_GREEN}${C_BOLD}  ╔══════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}  ║   ✅  Episódio gerado com sucesso!           ║${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}  ╚══════════════════════════════════════════════╝${C_RESET}"
    echo
    detail "🎬  $(basename "$mkv_final")"
    detail "🌅  $(basename "$thumb")"
    detail "🕐  Tempo: $(( duracao / 60 ))m $(( duracao % 60 ))s"
    echo
}

main "$@"
