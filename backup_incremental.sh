#!/bin/bash
BASE="caminho-do-hd"
DEST="$BASE/backup incremental"
LOG="$BASE/backup_samba.log"
CRED="$BASE/samba.cred"
DISCORD_CONF="$BASE/discord.conf"
PROXY_CURLRC="$BASE/proxy.curlrc"

source "$DISCORD_CONF"

export LC_ALL=C
trap 'mountpoint -q /mnt/samba && sudo umount /mnt/samba' EXIT

DATA_ATUAL=$(date +%Y-%m-%d)
DATA_ONTEM=$(date -d yesterday +%Y-%m-%d)
RESUMO=""

enviar_discord() {
  # Discord limita a mensagem a 2000 caracteres
  local MSG="${1:0:1900}"
  local JSON CODE

  # python monta o JSON já com aspas, quebras de linha e emojis escapados
  JSON=$(python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1]}))' "$MSG")

  CODE=$(curl -sS --max-time 20 -K "$PROXY_CURLRC" \
    -H "Content-Type: application/json" \
    -d "$JSON" \
    -o /dev/null -w "%{http_code}" \
    "$WEBHOOK_URL")

  # o Discord responde 204 quando o webhook funciona
  if [ "$CODE" != "204" ]; then
    echo "$(date): ERRO - envio ao Discord falhou (HTTP $CODE)" >> "$LOG"
  fi
}

fazer_backup() {
  local NOME="$1"
  local INICIO=$(date '+%H:%M:%S')
  local SAIDA="/tmp/rsync_${NOME}.txt"

  mkdir -p /mnt/samba
  sudo mount -t cifs "//IP-DO-SERVIDOR/$NOME" /mnt/samba -o credentials="$CRED"
  if ! mountpoint -q /mnt/samba; then
    echo "$(date): ERRO - Falha ao montar $NOME, backup abortado" >> "$LOG"
    RESUMO+="❌ **$NOME**: Falha ao montar o Samba"$'\n\n'
    return 1
  fi

  local LINK=()
  local TIPO="Completo"
  if [ -d "$DEST/$NOME/$DATA_ONTEM" ]; then
    TIPO="Parcial"
    LINK=(--link-dest="$DEST/$NOME/$DATA_ONTEM/")
  fi

  mkdir -p "$DEST/$NOME/$DATA_ATUAL"
  rsync -avH --stats "${LINK[@]}" /mnt/samba/ "$DEST/$NOME/$DATA_ATUAL/" > "$SAIDA" 2>&1
  local RC=$?
  sudo umount /mnt/samba

  local FIM=$(date '+%H:%M:%S')
  local ARQ=$(grep -E "Number of (regular )?files transferred" "$SAIDA" | awk -F': ' '{print $2}')
  local TAM=$(grep "Total transferred file size" "$SAIDA" | awk -F': ' '{print $2}')

  if [ "$RC" -eq 0 ] || [ "$RC" -eq 24 ]; then
    echo "$(date): SUCESSO - $NOME ($TIPO), ${ARQ:-0} arquivos" >> "$LOG"
    RESUMO+="✅ **$NOME** ($TIPO)"$'\n'"$INICIO → $FIM"$'\n'"Arquivos: ${ARQ:-0} | Tamanho: ${TAM:-0}"$'\n\n'
  else
    rm -rf "$DEST/$NOME/$DATA_ATUAL"
    echo "$(date): ERRO - rsync de $NOME saiu com o codigo $RC" >> "$LOG"
    RESUMO+="❌ **$NOME** ($TIPO): rsync falhou, codigo $RC"$'\n\n'
  fi
}

fazer_backup publico # funcao fazer_backup() + o nome da pasta (precisa ser exatamente igual ao nome da pasta que será copiada)
fazer_backup departamentos

enviar_discord "🗄️ **Backup Samba - $(date '+%d/%m/%Y')**"$'\n\n'"$RESUMO"
#desenvolvedor: CB-FN-IF MATHEUS GOMES
