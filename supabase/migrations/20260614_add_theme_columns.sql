alter table if exists configuracoes_sistema
  add column if not exists theme_name text not null default 'default';

alter table if exists configuracoes_sistema
  add column if not exists theme_dark boolean not null default false;
