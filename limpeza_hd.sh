#!/bin/bash
BASE="caminho-do-hd"
DEST="$BASE/backup incremental"
LOG="$BASE/backup_samba.log"
DISCORD_CONF="$BASE/discord.conf"
PROXY_CURLRC="$BASE/proxy.curlrc"
LIMITE_USO=85 # pode alterar para a porcentagem livre que desejar no HD

source "$DISCORD_CONF"
export LC_ALL=C

# trava compartilhada com o script de backup
exec 9>"$BASE/backup.lock"
flock -n 9 || { echo "$(date): limpeza abortada, backup em andamento" >> "$LOG"; exit 0; }

enviar_discord() {
  local MSG="${1:0:1900}" JSON CODE
  JSON=$(python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1]}))' "$MSG")
  CODE=$(curl -sS --max-time 20 -K "$PROXY_CURLRC" -H "Content-Type: application/json" \
    -d "$JSON" -o /dev/null -w "%{http_code}" "$WEBHOOK_URL")
  [ "$CODE" != "204" ] && echo "$(date): ERRO - Discord falhou (HTTP $CODE)" >> "$LOG"
}

uso_disco() { df --output=pcent "$BASE" | tail -1 | tr -dc '0-9'; }

# apaga o ciclo mais antigo de um compartilhamento; imprime "inicio -> fim"
apagar_cadeia_antiga() {
  local NOME="$1" D ANT PASTAS INICIOS=() PRIMEIRA="" ULTIMA=""

  mapfile -t PASTAS < <(find "$DEST/$NOME" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
                        | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort)

  for D in "${PASTAS[@]}"; do
    ANT=$(date -d "$D -1 day" +%Y-%m-%d)
    [ -d "$DEST/$NOME/$ANT" ] || INICIOS+=("$D")
  done

  [ "${#INICIOS[@]}" -lt 2 ] && return 1   # nunca apaga o único/atual

  local CORTE="${INICIOS[1]}"
  for D in "${PASTAS[@]}"; do
    [[ "$D" < "$CORTE" ]] || break
    [ -z "$D" ] && break
    [ -z "$PRIMEIRA" ] && PRIMEIRA="$D"
    ULTIMA="$D"
    rm -rf -- "$DEST/$NOME/$D"
    echo "$(date): REMOVIDO $NOME/$D" >> "$LOG"
  done
  echo "$PRIMEIRA → $ULTIMA"
}

[ "$(uso_disco)" -le "$LIMITE_USO" ] && exit 0

USO_ANTES=$(uso_disco)
RESUMO=""

while [ "$(uso_disco)" -gt "$LIMITE_USO" ]; do
  APAGOU=0
  for NOME in publico departamentos; do
    [ "$(uso_disco)" -le "$LIMITE_USO" ] && break
    if R=$(apagar_cadeia_antiga "$NOME"); then
      RESUMO+="🧹 $NOME: $R"$'\n'
      APAGOU=1
    fi
  done
  [ "$APAGOU" -eq 0 ] && { RESUMO+="⚠️ Só resta 1 ciclo por pasta, não dá para apagar mais. HD precisa crescer!"$'\n'; break; }
done

enviar_discord "🧹 **Limpeza de backups - $(date '+%d/%m/%Y')**"$'\n'"Disco: ${USO_ANTES}% → $(uso_disco)%"$'\n\n'"$RESUMO"
