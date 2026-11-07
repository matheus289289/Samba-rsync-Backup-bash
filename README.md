# samba-rsync-backup

Backup incremental automático de compartilhamentos Samba (CIFS) usando **rsync** e **hardlinks**, com limpeza automática de ciclos antigos quando o disco enche e **notificações no Discord** via webhook.

![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?logo=gnubash&logoColor=white)
![rsync](https://img.shields.io/badge/rsync-incremental-blue)
![Linux](https://img.shields.io/badge/Linux-Ubuntu-E95420?logo=ubuntu&logoColor=white)

## O que o projeto faz

São dois scripts que trabalham juntos:

| Script | Função |
|---|---|
| `backup_incremental.sh` | Monta cada compartilhamento Samba, copia com rsync para uma pasta com a data do dia e envia o resumo ao Discord |
| `limpeza.sh` | Quando o uso do disco passa do limite (padrão **85%**), apaga o ciclo de backup mais antigo de cada pasta até voltar ao limite |

## Como funciona

### Backup

1. Monta `//SERVIDOR/compartilhamento` em `/mnt/samba` usando credenciais de um arquivo.
2. Verifica se existe a pasta do dia anterior:
   - **Existe** → backup **parcial**: o rsync usa `--link-dest` apontando para ontem. Arquivos que não mudaram viram *hardlinks* (não ocupam espaço novo), e só o que foi alterado é copiado.
   - **Não existe** → backup **completo** (é o que acontece na segunda-feira, já que não há backup no fim de semana).
3. Cada dia fica numa pasta `AAAA-MM-DD`, e cada pasta parece um backup completo, mas só ocupa o espaço do que mudou.
4. Desmonta o Samba, registra no log e envia o resultado ao Discord.
5. Se o rsync falhar, a pasta incompleta do dia é removida, para não ficar um backup quebrado parecendo válido.

```
backup incremental/
├── publico/
│   ├── 2026-11-02/   <- completo (segunda)
│   ├── 2026-11-03/   <- parcial (hardlinks + alterações)
│   └── 2026-11-04/
└── departamentos/
    └── ...
```

### Limpeza

- Roda com **trava compartilhada** (`flock`) com o script de backup: se um backup está em andamento, a limpeza aborta.
- Identifica os **ciclos** (sequências de dias consecutivos que começam num backup completo).
- Apaga sempre o **ciclo mais antigo inteiro**, nunca pastas soltas, porque os hardlinks dependem da cadeia.
- **Nunca apaga o único ciclo existente**: se só sobrou um, avisa no Discord que o HD precisa crescer.

## Requisitos

- Linux (testado em Ubuntu)
- `rsync`, `cifs-utils`, `curl`, `python3`, `flock` (util-linux)
- Um webhook do Discord
- Permissão de `sudo` para `mount`/`umount` sem senha (veja abaixo)

```bash
sudo apt install rsync cifs-utils curl python3
```

## Configuração

### 1. Ajuste as variáveis no topo dos scripts

```bash
BASE="/caminho/do/seu/hd"      # disco onde ficam os backups e arquivos de apoio
LIMITE_USO=85                   # % de uso do disco que dispara a limpeza
```

Edite também o IP do servidor e os nomes dos compartilhamentos em `backup_incremental.sh`:

```bash
sudo mount -t cifs "//IP-DO-SERVIDOR/$NOME" /mnt/samba -o credentials="$CRED"
...
fazer_backup publico
fazer_backup departamentos
```

### 2. Crie os arquivos de apoio dentro de `$BASE`

**`samba.cred`**: credenciais do compartilhamento

```
username=USUARIO
password=SENHA
domain=DOMINIO
```

**`discord.conf`**: webhook do Discord

```bash
WEBHOOK_URL="https://discord.com/api/webhooks/ID/TOKEN"
```

**`proxy.curlrc`**: configuração do curl (use se sua rede exige proxy; pode ficar vazio se não precisar)

```
proxy = "http://proxy.exemplo:3128"
```

Proteja os arquivos com credenciais:

```bash
chmod 600 samba.cred discord.conf proxy.curlrc
```

### 3. Permita `mount`/`umount` sem senha

Se o cron roda com um usuário comum, adicione com `sudo visudo -f /etc/sudoers.d/backup-samba`:

```
usuario ALL=(root) NOPASSWD: /usr/bin/mount, /usr/bin/umount
```

### 4. Dê permissão de execução

```bash
chmod +x backup_incremental.sh limpeza.sh
```

## Agendamento (cron)

Exemplo: backup de segunda a sexta às 22h e limpeza às 06h:

```cron
0 22 * * 1-5 /caminho/backup_incremental.sh
0 6  * * 1-5 /caminho/limpeza.sh
```

## Logs e notificações

- Log em `$BASE/backup_samba.log` (sucessos, erros e pastas removidas).
- Mensagem no Discord ao fim de cada backup, com horário, número de arquivos e tamanho transferido.
- Mensagem no Discord a cada limpeza, com o uso do disco antes/depois e quais datas foram removidas.

## Segurança

- **Nunca** suba `samba.cred`, `discord.conf` ou `proxy.curlrc` para o GitHub. Use um `.gitignore`:

  ```
  *.cred
  discord.conf
  proxy.curlrc
  *.log
  ```
- Se o webhook do Discord vazar, apague-o no servidor e gere outro.

## Possíveis melhorias

- Verificação de integridade dos backups (checksum por amostragem)
- Retenção configurável por número de ciclos, além do limite de disco
- Suporte a mais de dois compartilhamentos por lista de configuração

## Autor

Desenvolvido por **Matheus Tavares Gomes**.

## Licença

Distribuído sob a licença MIT. Veja o arquivo `LICENSE`.
