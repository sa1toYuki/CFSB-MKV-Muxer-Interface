# 🎌 CFSB MKV Muxer

Script Bash para multiplexação de episódios de anime no padrão de fansub. Combina vídeo original, legenda `.ass` em PT-BR e capítulos em um único `.mkv` final com hash CRC-32 no nome, com opção de gerar uma thumbnail `.webp` do episódio.

---

## ✨ O que o script faz

1. Detecta automaticamente o `.mkv`, `.ass` e `.txt` na pasta informada — e recusa rodar se houver mais de um arquivo de qualquer um desses tipos na mesma pasta
2. Valida o arquivo de capítulos antes de prosseguir (precisa estar no formato `CHAPTERxx=`)
3. Verifica se há espaço em disco suficiente antes de iniciar o muxing
4. Coleta nome do anime, número do episódio e source via prompt interativo
5. Identifica codecs de vídeo (HEVC / AVC / AV1) e áudio (AAC / FLAC / Opus) e a resolução diretamente do arquivo de origem
6. Remove qualquer legenda já embutida no `.mkv` original (não importa quantas existam) e injeta apenas a legenda `.ass` fornecida
7. Multiplexa as faixas com `mkvmerge`, configurando idiomas e flags corretamente
8. Calcula o hash CRC-32 do arquivo final e renomeia com ele
9. Opcionalmente gera uma thumbnail `.webp` no timestamp escolhido

O arquivo de saída segue o padrão:
```
[CFSB] Nome do Anime - 01 [1080p][WEB][HEVC][AAC][A1B2C3D4].mkv
[CFSB] Nome do Anime - 01 [1080p][WEB][HEVC][AAC][A1B2C3D4].webp
```

---

## 📦 Dependências

| Ferramenta | Função |
|---|---|
| `mkvmerge` / `mkvinfo` | Multiplexação e análise do MKV (pacote `mkvtoolnix`) |
| `ffmpeg` | Geração da thumbnail (apenas se solicitada) |
| `crc32` ou `cfv` | Cálculo do hash CRC-32 |

### Linux

**Fedora / Nobara / RHEL:**
```bash
sudo dnf install mkvtoolnix ffmpeg perl-Archive-Zip
```

**Debian / Ubuntu:**
```bash
sudo apt install mkvtoolnix ffmpeg libarchive-zip-perl
```

**Arch:**
```bash
sudo pacman -S mkvtoolnix-cli ffmpeg perl-archive-zip
```

### Windows (WSL)

Instale o [WSL2](https://learn.microsoft.com/pt-br/windows/wsl/install) com Ubuntu e siga os comandos do Debian/Ubuntu acima.

---

## 🚀 Uso

### Estrutura de pasta esperada

Coloque na mesma pasta **um arquivo de cada tipo** antes de rodar — se houver mais de um `.mkv`, `.ass` ou `.txt`, o script para e avisa qual tipo está duplicado:

```
episodio/
├── video_original.mkv
├── legenda_ptbr.ass
└── capitulos.txt
```

### Executando

```bash
chmod +x cfsb_muxer.sh
./cfsb_muxer.sh /caminho/da/pasta
```

O script pede nome do anime e episódio por texto, e o source por um menu de seleção:

```
🎬 Nome do Anime      : Dragon Ball Z
📺 Número do Episódio : 042
💿 Source (↑/↓ + Enter, ou digite o número):
      BD
    ❯ WEB
      TV
      DVD
      HDTV
```

Navegue com as setas `↑`/`↓` e confirme com `Enter`, ou digite diretamente o número da opção (1 a 5).

Em seguida pergunta se deseja gerar thumbnail:

```
🌅 Gerar thumbnail? (s/N): s
⏱  Timestamp (padrão 00:00:30): 
```

Responder `n` (ou apenas `Enter`) pula a geração da thumbnail. Se responder `s`, pressionar `Enter` sem digitar nada usa o timestamp padrão (`00:00:30`); qualquer outro valor no formato `HH:MM:SS` é aceito.

---

## 📁 Formato do arquivo de capítulos

O `.txt` deve seguir o formato de capítulos do MKV — o script rejeita o arquivo se a primeira linha não bater com esse padrão:

```
CHAPTER01=00:00:00.000
CHAPTER01NAME=Abertura
CHAPTER02=00:01:30.000
CHAPTER02NAME=Parte A
```

---

## ⚙️ Detalhes técnicos

- Faixa de vídeo marcada como `ja-JP` (Japonês) com `--original-flag`
- Faixa de legenda marcada como `pt-BR` (Português do Brasil)
- `--track-order` é montado dinamicamente a partir da contagem real de faixas de vídeo/áudio do arquivo de origem, em vez de assumir um layout fixo — funciona corretamente mesmo se o `.mkv` original tiver legendas internas, que são sempre descartadas
- Nomes de capítulos gerados automaticamente como `Capítulo 01`, `Capítulo 02`...
- Hash CRC-32 calculado após muxing e inserido no nome final do arquivo
- Thumbnail (quando gerada) extraída em `.webp` com filtro `thumbnail,setsar=1`
- Verificação de espaço em disco compara o espaço livre na pasta de destino com o tamanho do `.mkv` de origem antes de iniciar
- Arquivo temporário (`_TEMP.mkv`) e cursor do terminal são limpos automaticamente se o script for interrompido (Ctrl+C) ou falhar no meio do processo
- Cores e spinner desativados automaticamente quando stdout não é um TTY (útil para logs/pipes)
