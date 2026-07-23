create table if not exists banca_pareceristas (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  id_externo text not null,
  nome text not null,
  email text not null,
  instituicao text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists banca_pareceristas_environment_id_externo_idx
  on banca_pareceristas(environment, id_externo);

create table if not exists banca_avaliacoes (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('homolog', 'producao')),
  inscricao_id_externo text not null,
  parecerista_id_externo text not null,
  status text not null default 'nao_iniciada',
  parecer_geral text,
  concluida boolean not null default false,
  motivo_curta_duracao text,
  notas_json jsonb not null default '[]'::jsonb,
  justificativas_json jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists banca_avaliacoes_environment_unique_idx
  on banca_avaliacoes(environment, inscricao_id_externo, parecerista_id_externo);

create table if not exists banca_avaliacao_criterios (
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

create unique index if not exists banca_avaliacao_criterios_environment_unique_idx
  on banca_avaliacao_criterios(environment, inscricao_id_externo, parecerista_id_externo, criterio_ordem);

alter table banca_pareceristas enable row level security;
alter table banca_avaliacoes enable row level security;
alter table banca_avaliacao_criterios enable row level security;

drop policy if exists "prototype full access banca_pareceristas" on banca_pareceristas;
create policy "prototype full access banca_pareceristas" on banca_pareceristas for all using (true) with check (true);
drop policy if exists "prototype full access banca_avaliacoes" on banca_avaliacoes;
create policy "prototype full access banca_avaliacoes" on banca_avaliacoes for all using (true) with check (true);
drop policy if exists "prototype full access banca_avaliacao_criterios" on banca_avaliacao_criterios;
create policy "prototype full access banca_avaliacao_criterios" on banca_avaliacao_criterios for all using (true) with check (true);

comment on table banca_pareceristas is 'Pareceristas da segunda rodada (banca), isolados dos pareceristas da avaliação inicial.';
comment on table banca_avaliacoes is 'Avaliações da banca; nunca sobrescrevem a tabela avaliacoes da primeira rodada.';
