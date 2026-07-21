alter table if exists configuracoes_sistema
  add column if not exists banca_selecionados jsonb;

comment on column configuracoes_sistema.banca_selecionados is
  'IDs externos das equipes selecionadas para a banca, separados por ambiente.';
