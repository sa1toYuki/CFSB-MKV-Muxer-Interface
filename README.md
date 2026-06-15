# 🎌 CFSB MKV Muxer

Script Bash para multiplexação de episódios de anime no padrão de fansub. Combina vídeo original, legenda `.ass` em PT-BR e capítulos em um único `.mkv` final com hash CRC-32 no nome, além de gerar uma thumbnail `.webp` do episódio.

---

## ✨ O que o script faz

1. Detecta automaticamente os arquivos `.mkv`, `.ass` e `.txt` na pasta informada
2. Coleta nome do anime, número do episódio, source e tempo para gerar a thumbnail via prompt interativo
3. Identifica codecs de vídeo (HEVC / AVC / AV1) e áudio (AAC / FLAC / Opus) e resolução diretamente do arquivo
4. Multiplexa as faixas com `mkvmerge`, configurando idiomas e flags corretamente
5. Calcula o hash CRC-32 do arquivo final e renomeia com ele
6. Gera uma thumbnail `.webp` a partir do tempo especificado pelo usuário

O arquivo de saída segue o padrão:
```
[CFSB] Nome do Anime - 01 [1080p][WEB-DL][HEVC][AAC][A1B2C3D4].mkv
[CFSB] Nome do Anime - 01 [1080p][WEB-DL][HEVC][AAC][A1B2C3D4].webp
```

---

## 📦 Dependências

| Ferramenta | Função |
|---|---|
| `mkvmerge` / `mkvinfo` | Multiplexação e análise do MKV (pacote `mkvtoolnix`) |
| `ffmpeg` | Geração da thumbnail |
| `crc32` ou `perl` com `Digest::CRC32` | Cálculo do hash CRC-32 |

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

Coloque na mesma pasta **um arquivo de cada tipo** antes de rodar:

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

O script vai pedir quatro informações:

```
🎬 Nome do Anime      : Dragon Ball Z
📺 Número do Episódio : 042
💿 Source             : WEB-DL
📸 Tempo para gerar thumbnail (segundos) [30] : 60
```

---

## 📁 Formato do arquivo de capítulos

O `.txt` deve seguir o formato de capítulos do MKV:

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
- Nomes de capítulos gerados automaticamente como `Capítulo 01`, `Capítulo 02`...
- Hash CRC-32 calculado após muxing e inserido no nome final do arquivo
- Thumbnail extraída em `.webp` no timestamp especificado pelo usuário com filtro `thumbnail,setsar=1`
- Cores e spinner desativados automaticamente quando stdout não é um TTY (útil para logs/pipes)
