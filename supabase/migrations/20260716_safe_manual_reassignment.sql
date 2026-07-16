-- Realocação individual segura de uma atribuição.
-- A função pode ser instalada durante as avaliações porque só altera dados
-- quando o admin confirma uma realocação. Os gatilhos documentados ao final
-- permanecem desativados até uma janela controlada de manutenção.

create or replace function public.realocar_atribuicao_segura(
  p_environment text,
  p_inscricao_id_externo text,
  p_parecerista_origem text,
  p_parecerista_destino text,
  p_actor_id text default 'admin'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_atribuicao public.atribuicoes%rowtype;
  v_destino public.pareceristas%rowtype;
  v_instituicao_time text;
  v_capacidade integer;
  v_carga integer;
  v_correlation_id text := gen_random_uuid()::text;
begin
  if p_environment not in ('homolog', 'producao') then
    raise exception 'Ambiente inválido.';
  end if;
  if coalesce(trim(p_parecerista_origem), '') = ''
     or coalesce(trim(p_parecerista_destino), '') = ''
     or p_parecerista_origem = p_parecerista_destino then
    raise exception 'Pareceristas de origem e destino devem ser diferentes.';
  end if;

  select * into v_atribuicao
  from public.atribuicoes
  where environment = p_environment
    and inscricao_id_externo = p_inscricao_id_externo
    and parecerista_id_externo = p_parecerista_origem
    and ativo = true
  for update;

  if not found then
    raise exception 'A atribuição de origem não está mais ativa.';
  end if;

  -- A linha do parecerista funciona como trava para serializar carga concorrente.
  select * into v_destino
  from public.pareceristas
  where environment = p_environment
    and id_externo = p_parecerista_destino
    and ativo = true
  for update;

  if not found or v_destino.is_teste then
    raise exception 'O parecerista de destino não é elegível.';
  end if;

  if exists (
    select 1 from public.atribuicoes
    where environment = p_environment
      and inscricao_id_externo = p_inscricao_id_externo
      and parecerista_id_externo = p_parecerista_destino
      and ativo = true
  ) then
    raise exception 'O parecerista de destino já está atribuído a este time.';
  end if;

  select instituicao into v_instituicao_time
  from public.inscricoes
  where environment = p_environment
    and id_externo = p_inscricao_id_externo
    and ativo = true
  for share;

  if not found then
    raise exception 'O time não foi encontrado ou está inativo.';
  end if;

  if coalesce(trim(v_instituicao_time), '') <> ''
     and coalesce(trim(v_destino.instituicao), '') <> ''
     and lower(regexp_replace(trim(v_instituicao_time), '\s+', ' ', 'g')) =
         lower(regexp_replace(trim(v_destino.instituicao), '\s+', ' ', 'g')) then
    raise exception 'Conflito institucional identificado para o destino.';
  end if;

  v_capacidade := coalesce(v_destino.capacidade_manual, v_destino.capacidade_calculada, 0);
  select count(*) into v_carga
  from public.atribuicoes
  where environment = p_environment
    and parecerista_id_externo = p_parecerista_destino
    and ativo = true;

  -- Qualquer conteúdo persistido na avaliação de origem torna a troca proibida.
  if exists (
    select 1
    from public.avaliacoes a
    where a.environment = p_environment
      and a.inscricao_id_externo = p_inscricao_id_externo
      and a.parecerista_id_externo = p_parecerista_origem
      and (
        a.concluida
        or coalesce(a.status, 'nao_iniciada') <> 'nao_iniciada'
        or coalesce(trim(a.parecer_geral), '') <> ''
        or coalesce(trim(a.motivo_curta_duracao), '') <> ''
        or exists (
          select 1 from jsonb_array_elements_text(coalesce(a.notas_json, '[]'::jsonb)) as item(valor)
          where coalesce(trim(valor), '') <> ''
        )
        or exists (
          select 1 from jsonb_array_elements_text(coalesce(a.justificativas_json, '[]'::jsonb)) as item(valor)
          where coalesce(trim(valor), '') <> ''
        )
      )
  ) or exists (
    select 1
    from public.avaliacao_criterios c
    where c.environment = p_environment
      and c.inscricao_id_externo = p_inscricao_id_externo
      and c.parecerista_id_externo = p_parecerista_origem
      and (coalesce(trim(c.nota), '') <> '' or coalesce(trim(c.justificativa), '') <> '')
  ) then
    raise exception 'A avaliação de origem já possui conteúdo salvo; nenhuma alteração foi realizada.';
  end if;

  -- Primeiro encerra o par antigo e depois ativa/cria o novo, preservando a ordem.
  update public.atribuicoes
  set ativo = false
  where id = v_atribuicao.id;

  insert into public.atribuicoes (
    environment, inscricao_id_externo, parecerista_id_externo, ordem, origem, ativo
  ) values (
    p_environment, p_inscricao_id_externo, p_parecerista_destino,
    v_atribuicao.ordem, 'realocacao_manual', true
  )
  on conflict (environment, inscricao_id_externo, parecerista_id_externo)
  do update set
    ordem = excluded.ordem,
    origem = 'realocacao_manual',
    ativo = true;

  insert into public.eventos_auditoria (
    environment, event_type, actor_type, actor_id, inscricao_id,
    parecerista_id, correlation_id, payload_json
  ) values (
    p_environment, 'atribuicao_realocada', 'admin', coalesce(nullif(trim(p_actor_id), ''), 'admin'),
    p_inscricao_id_externo, p_parecerista_destino, v_correlation_id,
    jsonb_build_object(
      'parecerista_origem', p_parecerista_origem,
      'parecerista_destino', p_parecerista_destino,
      'ordem_preservada', v_atribuicao.ordem,
      'carga_destino_antes', v_carga,
      'capacidade_destino', v_capacidade,
      'acima_capacidade_apos_troca', v_capacidade > 0 and (v_carga + 1) > v_capacidade
    )
  );

  return jsonb_build_object(
    'ok', true,
    'correlation_id', v_correlation_id,
    'inscricao_id_externo', p_inscricao_id_externo,
    'parecerista_origem', p_parecerista_origem,
    'parecerista_destino', p_parecerista_destino,
    'ordem', v_atribuicao.ordem
  );
end;
$$;

/*
  PROTEÇÃO ADIADA PARA UMA JANELA DE MANUTENÇÃO.
  O bloco abaixo é mantido como documentação, mas não será instalado agora para
  não alterar o comportamento de gravação das avaliações que já estão em curso.

-- Impede que uma aba antiga salve depois que o par deixou de estar ativo.
create or replace function public.validar_atribuicao_ativa_avaliacao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(new.is_teste, false) then
    return new;
  end if;
  if not exists (
    select 1 from public.atribuicoes at
    where at.environment = new.environment
      and at.inscricao_id_externo = new.inscricao_id_externo
      and at.parecerista_id_externo = new.parecerista_id_externo
      and at.ativo = true
  ) then
    raise exception 'A atribuição não está mais ativa; a avaliação não foi salva.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_atribuicao_ativa_avaliacao on public.avaliacoes;
create trigger trg_validar_atribuicao_ativa_avaliacao
before insert or update on public.avaliacoes
for each row execute function public.validar_atribuicao_ativa_avaliacao();

create or replace function public.validar_atribuicao_ativa_criterio()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.atribuicoes at
    where at.environment = new.environment
      and at.inscricao_id_externo = new.inscricao_id_externo
      and at.parecerista_id_externo = new.parecerista_id_externo
      and at.ativo = true
  ) and not exists (
    select 1 from public.avaliacoes av
    where av.environment = new.environment
      and av.inscricao_id_externo = new.inscricao_id_externo
      and av.parecerista_id_externo = new.parecerista_id_externo
      and av.is_teste = true
  ) then
    raise exception 'A atribuição não está mais ativa; o critério não foi salvo.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_atribuicao_ativa_criterio on public.avaliacao_criterios;
create trigger trg_validar_atribuicao_ativa_criterio
before insert or update on public.avaliacao_criterios
for each row execute function public.validar_atribuicao_ativa_criterio();
*/

-- O protótipo atual usa a chave anon no admin. Em produção, substituir este
-- grant por autenticação administrativa ou Edge Function antes da implantação.
revoke all on function public.realocar_atribuicao_segura(text, text, text, text, text) from public;
grant execute on function public.realocar_atribuicao_segura(text, text, text, text, text) to anon, authenticated;
