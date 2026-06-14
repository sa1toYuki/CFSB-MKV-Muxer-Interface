#!/usr/bin/env bash

set -euo pipefail

# ─── Constantes ───────────────────────────────────────────────────────────────
readonly SCRIPT_NAME="$(basename "$0")"
readonly TAG="CFSB"
readonly THUMB_TS="${THUMB_TS:-00:03:00}"

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

# ─── Spinner ──────────────────────────────────────────────────────────────────
spinner() {
    local label="$1"; shift
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local tmp_out tmp_err exit_code=0

    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    # Restaura cursor em sinal de interrupção
    trap 'tput cnorm 2>/dev/null || true; rm -f "$tmp_out" "$tmp_err"; exit 130' INT TERM

    "$@" >"$tmp_out" 2>"$tmp_err" &
    local pid=$!

    tput civis 2>/dev/null || true

    while kill -0 "$pid" 2>/dev/null; do
        echo -ne "\r${C_CYAN}  ${frames[$i]}  ${C_RESET}${C_BOLD}${label}${C_RESET}   "
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.08
    done

    wait "$pid" || exit_code=$?

    tput cnorm 2>/dev/null || true
    trap - INT TERM
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

# ─── Detecção de faixas (JSON único) ──────────────────────────────────────────
detect_tracks() {
    local file="$1"
    _MKV_JSON=$(mkvmerge -J "$file")
}

parse_video_codec() {
    local info
    info=$(echo "$_MKV_JSON" | grep -i '"codec_id"' | grep -i 'V_' | head -n 1 || true)
    # Fallback: usa identify para HEVC/AVC/AV1
    local identify
    identify=$(mkvmerge --identify "$1" | grep -i "video" || true)

    if   [[ "$identify" == *"HEVC"* || "$identify" == *"H.265"* ]]; then echo "HEVC"
    elif [[ "$identify" == *"AVC"*  || "$identify" == *"H.264"* ]]; then echo "AVC"
    elif [[ "$identify" == *"AV1"* ]];                               then echo "AV1"
    else
        warn "Codec de vídeo não reconhecido, assumindo HEVC"
        echo "HEVC"
    fi
}

parse_audio_codec() {
    local identify
    identify=$(mkvmerge --identify "$1" | grep -i "audio" | head -n 1 || true)

    if   [[ "$identify" == *"AAC"* ]];  then echo "AAC"
    elif [[ "$identify" == *"FLAC"* ]]; then echo "FLAC"
    elif [[ "$identify" == *"Opus"* ]]; then echo "Opus"
    else
        warn "Codec de áudio não reconhecido, assumindo AAC"
        echo "AAC"
    fi
}

parse_resolution() {
    local altura
    altura=$(echo "$_MKV_JSON" \
        | grep -oP '"display_dimensions":\s*"\d+x\K\d+' \
        | head -n 1)

    if [[ -z "$altura" ]]; then
        altura=$(echo "$_MKV_JSON" \
            | grep -oP '"pixel_dimensions":\s*"\d+x\K\d+' \
            | head -n 1)
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

    # Localiza arquivos de entrada — exige exatamente 1 de cada
    local -a mkv_files ass_files txt_files
    mapfile -t mkv_files < <(find "$pasta" -maxdepth 1 -type f -name "*.mkv" | sort)
    mapfile -t ass_files < <(find "$pasta" -maxdepth 1 -type f -name "*.ass" | sort)
    mapfile -t txt_files < <(find "$pasta" -maxdepth 1 -type f -name "*.txt" | sort)

    (( ${#mkv_files[@]} == 1 )) || die "Esperado 1 arquivo .mkv, encontrado ${#mkv_files[@]} em: $pasta"
    (( ${#ass_files[@]} == 1 )) || die "Esperado 1 arquivo .ass, encontrado ${#ass_files[@]} em: $pasta"
    (( ${#txt_files[@]} == 1 )) || die "Esperado 1 arquivo .txt, encontrado ${#txt_files[@]} em: $pasta"

    local mkv_original="${mkv_files[0]}"
    local legenda="${ass_files[0]}"
    local capitulos="${txt_files[0]}"

    info "Arquivos detectados"
    detail "🎞  $(basename "$mkv_original")"
    detail "💬  $(basename "$legenda")"
    detail "📖  $(basename "$capitulos")"

    prompt_user

    local tempo_inicial=$SECONDS

    # ── Detecta codecs e resolução (1 chamada mkvmerge -J) ──
    step "Analisando faixas de mídia..."
    detect_tracks "$mkv_original"

    local video_codec audio_codec qualidade
    video_codec=$(parse_video_codec "$mkv_original")
    audio_codec=$(parse_audio_codec "$mkv_original")
    qualidade=$(parse_resolution)

    success "Análise concluída"
    detail "🎥  Vídeo    : ${C_BOLD}${video_codec}${C_RESET}"
    detail "🔊  Áudio    : ${C_BOLD}${audio_codec}${C_RESET}"
    detail "📐  Resolução: ${C_BOLD}${qualidade}${C_RESET}"
    echo

    # ── Monta nomes ──
    local nome_base mkv_temp mkv_final
    nome_base="[$TAG] ${ANIME} - ${EPISODIO} [${qualidade}][${SOURCE}][${video_codec}][${audio_codec}]"
    mkv_temp="${pasta}/${nome_base}_TEMP.mkv"

    rm -f "$mkv_temp"

    # ── Muxing ──
    spinner "Multiplexando faixas..." \
        mkvmerge \
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

    # ── CRC-32 (direto, sem subshell serializado) ──
    step "Calculando CRC-32..."
    local hash
    hash=$(calc_crc32 "$mkv_temp")
    success "CRC-32: ${C_BOLD}${hash}${C_RESET}"

    mkv_final="${pasta}/${nome_base}[${hash}].mkv"
    mv -- "$mkv_temp" "$mkv_final"

    # ── Thumbnail ──
    spinner "Gerando thumbnail (ts=${THUMB_TS})..." \
        ffmpeg -ss "$THUMB_TS" -i "$mkv_final" -vf "thumbnail,setsar=1" -vframes 1 \
            "${pasta}/${nome_base}[${hash}].webp" -y

    local thumb="${pasta}/${nome_base}[${hash}].webp"

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
