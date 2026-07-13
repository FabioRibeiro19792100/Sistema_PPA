# Supabase do Sistema PPA

Este diretório prepara o projeto para operar com **um único projeto Supabase** e dois ambientes lógicos separados pela coluna `environment`:

- `homolog`
- `producao`

O mesmo schema SQL é aplicado uma vez no projeto:

- [schema.sql](/Users/fabioribeiro/Documents/SistemaPPA/supabase/schema.sql)

## Como aplicar

1. Criar um projeto no Supabase.
2. Abrir o SQL Editor desse projeto.
3. Executar o conteúdo de `schema.sql`.
4. Copiar a `Project URL` e a `anon key`.
5. Colar essas credenciais na tela `Configurações > Persistência e ambientes` do app.
6. No app, alternar entre `homolog` e `producao` pelo seletor `Ambiente ativo`.

## Edge Function para anexos

Para que PDFs e alguns anexos hospedados em `inscricoes.led.globo` possam abrir dentro do modal da ficha do parecerista, publique também a edge function:

- `supabase/functions/file-proxy/index.ts`
- `supabase/config.toml`

Deploy sugerido:

1. Instalar e autenticar a CLI do Supabase.
2. O arquivo `supabase/config.toml` mantém `verify_jwt = false` em `[functions.file-proxy]`, porque o modal do parecerista consome o proxy sem sessão autenticada do Supabase.
3. No diretório do projeto, executar:
   - `supabase functions deploy file-proxy`

Depois do deploy, o frontend passa a usar automaticamente:

- `https://<project-ref>.supabase.co/functions/v1/file-proxy?url=...`

Esse proxy remove o bloqueio de `frame-ancestors` / `x-frame-options` do arquivo original, permitindo a abertura no modal sem exigir nenhuma ação extra do parecerista.

Além disso, ele encaminha requisições parciais (`Range`) para melhorar o carregamento de vídeos dentro do modal.

## Observação importante sobre RLS

O schema atual foi deixado com políticas amplas de protótipo para permitir que o frontend comece a sincronizar imediatamente via `anon key`.

Antes de produção, o próximo endurecimento obrigatório é:

- trocar as policies abertas por policies baseadas em papel;
- separar `admin` e `parecerista`;
- restringir leitura/escrita por ambiente e identidade.

## Fluxo esperado

- Em `homolog`, a planilha atual entra como base oficial do ambiente.
- Em `produção`, outra planilha entra como base oficial do ambiente.
- Os dois ambientes ficam no mesmo banco, separados por `environment`.
- Depois da importação, o banco passa a ser a fonte oficial da operação.

## Backups

Use o script-base em:

- [backup_daily.example.sh](/Users/fabioribeiro/Documents/SistemaPPA/supabase/backup_daily.example.sh)

Ele é um template para snapshot diário externo por ambiente.
