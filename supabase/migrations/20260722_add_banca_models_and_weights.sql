alter table configuracoes_sistema
  add column if not exists banca_modelo_ativo text not null default 'grade_completa';

alter table configuracoes_sistema
  add column if not exists banca_modelos_config jsonb not null default '{"grade_completa":{"pesos":[12.5,12.5,12.5,12.5,12.5,12.5,12.5,12.5]},"grade_banca":{"pesos":[25,25,25,25]},"nota_direta":{"pesos":[100]}}'::jsonb;

alter table banca_avaliacoes
  add column if not exists modelo_id text not null default 'grade_completa';

alter table banca_avaliacao_criterios
  add column if not exists modelo_id text not null default 'grade_completa';

drop index if exists banca_avaliacoes_environment_unique_idx;
create unique index if not exists banca_avaliacoes_environment_model_unique_idx
  on banca_avaliacoes(environment, inscricao_id_externo, parecerista_id_externo, modelo_id);

drop index if exists banca_avaliacao_criterios_environment_unique_idx;
create unique index if not exists banca_avaliacao_criterios_environment_model_unique_idx
  on banca_avaliacao_criterios(environment, inscricao_id_externo, parecerista_id_externo, modelo_id, criterio_ordem);

alter table configuracoes_sistema
  drop constraint if exists configuracoes_sistema_banca_modelo_ativo_check;
alter table configuracoes_sistema
  add constraint configuracoes_sistema_banca_modelo_ativo_check
  check (banca_modelo_ativo in ('grade_completa', 'grade_banca', 'nota_direta'));

comment on column configuracoes_sistema.banca_modelo_ativo is 'Modelo atualmente exibido no portal e no ranking da banca.';
comment on column banca_avaliacoes.modelo_id is 'Modelo utilizado nesta avaliação; permite preservar avaliações de modelos anteriores.';
