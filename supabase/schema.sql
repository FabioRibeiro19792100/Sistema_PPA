create extension if not exists pgcrypto;

create table if not exists imports (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  source_name text not null,
  source_hash text not null,
  source_type text not null default 'xlsx',
  status text not null default 'completed',
  imported_at timestamptz not null default now(),
  imported_by text,
  row_count integer not null default 0,
  participant_row_count integer not null default 0,
  created_at timestamptz not null default now()
);

create unique index if not exists imports_environment_hash_idx
  on imports(environment, source_hash);

create table if not exists import_rows_raw (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references imports(id) on delete cascade,
  environment text not null check (environment in ('homolog', 'producao')),
  source_sheet text not null,
  row_number integer not null,
  payload_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists inscricoes (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  import_id uuid references imports(id) on delete set null,
  id_externo text not null,
  id_curto text not null,
  lider text not null,
  lider_email text,
  participante_2_nome text,
  participante_2_email text,
  participante_3_nome text,
  participante_3_email text,
  mentor_nome text,
  mentor_email text,
  instituicao text,
  modalidade text,
  uf text,
  curso text,
  ia_descricao text,
  objetivos_campanha text,
  estrategia_distribuicao text,
  defesa_conceitual text,
  video_url text,
  roteiro_30_url text,
  campanha_url text,
  raw_json jsonb not null default '{}'::jsonb,
  ativo boolean not null default true,
  source_import_hash text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists inscricoes_environment_id_externo_idx
  on inscricoes(environment, id_externo);

create table if not exists participantes (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  inscricao_id_externo text not null,
  papel text not null,
  ordem integer not null default 1,
  nome text not null,
  email text,
  instituicao text,
  uf text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists participantes_environment_unique_idx
  on participantes(environment, inscricao_id_externo, papel, ordem);

create table if not exists pareceristas (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  id_externo text not null,
  nome text not null,
  email text not null,
  instituicao text,
  is_teste boolean not null default false,
  capacidade_manual integer,
  capacidade_calculada integer not null default 0,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists pareceristas_environment_id_externo_idx
  on pareceristas(environment, id_externo);

create table if not exists atribuicoes (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  inscricao_id_externo text not null,
  parecerista_id_externo text not null,
  ordem integer not null default 1,
  origem text not null default 'automatica',
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists atribuicoes_environment_unique_idx
  on atribuicoes(environment, inscricao_id_externo, parecerista_id_externo);

create table if not exists avaliacoes (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  inscricao_id_externo text not null,
  parecerista_id_externo text not null,
  is_teste boolean not null default false,
  status text not null default 'nao_iniciada',
  parecer_geral text,
  concluida boolean not null default false,
  motivo_curta_duracao text,
  notas_json jsonb not null default '[]'::jsonb,
  justificativas_json jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists avaliacoes_environment_unique_idx
  on avaliacoes(environment, inscricao_id_externo, parecerista_id_externo);

alter table if exists pareceristas
  add column if not exists is_teste boolean not null default false;

alter table if exists avaliacoes
  add column if not exists is_teste boolean not null default false;

create table if not exists avaliacao_criterios (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  inscricao_id_externo text not null,
  parecerista_id_externo text not null,
  criterio_ordem integer not null,
  criterio_nome text not null,
  criterio_grupo text not null,
  nota text,
  justificativa text,
  created_at timestamptz not null default now()
);

create unique index if not exists avaliacao_criterios_environment_unique_idx
  on avaliacao_criterios(environment, inscricao_id_externo, parecerista_id_externo, criterio_ordem);

create table if not exists distribuicoes (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  origem text not null default 'manual_sync',
  parametros_json jsonb not null default '{}'::jsonb,
  cobertura_inscricoes integer not null default 0,
  total_slots integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists configuracoes_sistema (
  id text primary key,
  environment text not null check (environment in ('homolog', 'producao')),
  tempo_minimo_ms integer not null default 120000,
  insuf_obriga_parecer integer not null default 3,
  pareceres_por_equipe integer not null default 3,
  evitar_conflito_institucional boolean not null default true,
  criterios_pesos jsonb not null default '[12.5,12.5,12.5,12.5,12.5,12.5,12.5,12.5]'::jsonb,
  theme_name text not null default 'default',
  theme_dark boolean not null default false,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists eventos_auditoria (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  event_type text not null,
  actor_type text not null,
  actor_id text not null,
  inscricao_id text,
  parecerista_id text,
  correlation_id text,
  payload_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists eventos_auditoria_environment_created_idx
  on eventos_auditoria(environment, created_at desc);

create unique index if not exists eventos_auditoria_environment_event_corr_idx
  on eventos_auditoria(environment, event_type, correlation_id);

create table if not exists backups_log (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  backup_type text not null default 'daily_snapshot',
  backup_target text,
  status text not null default 'pending',
  details_json jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

alter table imports enable row level security;
alter table import_rows_raw enable row level security;
alter table inscricoes enable row level security;
alter table participantes enable row level security;
alter table pareceristas enable row level security;
alter table atribuicoes enable row level security;
alter table avaliacoes enable row level security;
alter table avaliacao_criterios enable row level security;
alter table distribuicoes enable row level security;
alter table configuracoes_sistema enable row level security;
alter table eventos_auditoria enable row level security;
alter table backups_log enable row level security;

drop policy if exists "prototype full access imports" on imports;
create policy "prototype full access imports" on imports for all using (true) with check (true);
drop policy if exists "prototype full access import_rows_raw" on import_rows_raw;
create policy "prototype full access import_rows_raw" on import_rows_raw for all using (true) with check (true);
drop policy if exists "prototype full access inscricoes" on inscricoes;
create policy "prototype full access inscricoes" on inscricoes for all using (true) with check (true);
drop policy if exists "prototype full access participantes" on participantes;
create policy "prototype full access participantes" on participantes for all using (true) with check (true);
drop policy if exists "prototype full access pareceristas" on pareceristas;
create policy "prototype full access pareceristas" on pareceristas for all using (true) with check (true);
drop policy if exists "prototype full access atribuicoes" on atribuicoes;
create policy "prototype full access atribuicoes" on atribuicoes for all using (true) with check (true);
drop policy if exists "prototype full access avaliacoes" on avaliacoes;
create policy "prototype full access avaliacoes" on avaliacoes for all using (true) with check (true);
drop policy if exists "prototype full access avaliacao_criterios" on avaliacao_criterios;
create policy "prototype full access avaliacao_criterios" on avaliacao_criterios for all using (true) with check (true);
drop policy if exists "prototype full access distribuicoes" on distribuicoes;
create policy "prototype full access distribuicoes" on distribuicoes for all using (true) with check (true);
drop policy if exists "prototype full access configuracoes_sistema" on configuracoes_sistema;
create policy "prototype full access configuracoes_sistema" on configuracoes_sistema for all using (true) with check (true);
drop policy if exists "prototype full access eventos_auditoria" on eventos_auditoria;
create policy "prototype full access eventos_auditoria" on eventos_auditoria for all using (true) with check (true);
drop policy if exists "prototype full access backups_log" on backups_log;
create policy "prototype full access backups_log" on backups_log for all using (true) with check (true);
