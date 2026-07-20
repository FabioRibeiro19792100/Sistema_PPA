alter table if exists configuracoes_sistema
  add column if not exists criterios_pesos jsonb
  not null
  default '[12.5,12.5,12.5,12.5,12.5,12.5,12.5,12.5]'::jsonb;

comment on column configuracoes_sistema.criterios_pesos is
  'Pesos percentuais dos oito critérios, na ordem da grade de avaliação; a soma deve ser 100.';
