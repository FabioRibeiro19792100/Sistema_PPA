-- Redistribuição atômica de atribuições ainda não iniciadas.
-- A função só altera dados quando o admin confirma explicitamente o lote.

create or replace function public.redistribuir_atribuicoes_pendentes_segura(
  p_environment text,
  p_parecerista_origem text,
  p_movimentos jsonb,
  p_actor_id text default 'admin'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_move jsonb;
  v_inscricao text;
  v_destino_id text;
  v_atribuicao public.atribuicoes%rowtype;
  v_destino public.pareceristas%rowtype;
  v_instituicao_time text;
  v_batch_id text := gen_random_uuid()::text;
  v_total integer := 0;
  v_destinos integer := 0;
begin
  if p_environment not in ('homolog', 'producao') then
    raise exception 'Ambiente inválido.';
  end if;
  if coalesce(trim(p_parecerista_origem), '') = '' then
    raise exception 'Parecerista de origem inválido.';
  end if;
  if p_movimentos is null or jsonb_typeof(p_movimentos) <> 'array' or jsonb_array_length(p_movimentos) = 0 then
    raise exception 'O lote de movimentos está vazio.';
  end if;

  if exists (
    select 1
    from (
      select item->>'inscricao_id_externo' as inscricao, count(*)
      from jsonb_array_elements(p_movimentos) item
      group by item->>'inscricao_id_externo'
      having count(*) > 1
    ) duplicados
  ) then
    raise exception 'O lote contém inscrições duplicadas.';
  end if;

  select count(distinct item->>'parecerista_destino') into v_destinos
  from jsonb_array_elements(p_movimentos) item;
  if v_destinos < 1 then
    raise exception 'O lote deve usar ao menos um destino efetivo.';
  end if;

  -- A função inteira roda em uma transação. Qualquer exceção reverte todo o lote.
  for v_move in
    select item
    from jsonb_array_elements(p_movimentos) item
    order by item->>'inscricao_id_externo'
  loop
    v_inscricao := trim(v_move->>'inscricao_id_externo');
    v_destino_id := trim(v_move->>'parecerista_destino');
    if coalesce(v_inscricao, '') = '' or coalesce(v_destino_id, '') = '' then
      raise exception 'Movimento com inscrição ou destino inválido.';
    end if;
    if v_destino_id = p_parecerista_origem then
      raise exception 'Origem e destino não podem ser iguais (%).', v_inscricao;
    end if;

    select * into v_atribuicao
    from public.atribuicoes
    where environment = p_environment
      and inscricao_id_externo = v_inscricao
      and parecerista_id_externo = p_parecerista_origem
      and ativo = true
    for update;
    if not found then
      raise exception 'A atribuição de origem não está mais ativa (%).', v_inscricao;
    end if;

    select * into v_destino
    from public.pareceristas
    where environment = p_environment
      and id_externo = v_destino_id
      and ativo = true
    for update;
    if not found or v_destino.is_teste then
      raise exception 'Destino não elegível para a inscrição %.', v_inscricao;
    end if;

    if exists (
      select 1 from public.atribuicoes
      where environment = p_environment
        and inscricao_id_externo = v_inscricao
        and parecerista_id_externo = v_destino_id
        and ativo = true
    ) then
      raise exception 'O destino já está atribuído à inscrição %.', v_inscricao;
    end if;

    select instituicao into v_instituicao_time
    from public.inscricoes
    where environment = p_environment
      and id_externo = v_inscricao
      and ativo = true
    for share;
    if not found then
      raise exception 'Inscrição inexistente ou inativa (%).', v_inscricao;
    end if;

    if coalesce(trim(v_instituicao_time), '') <> ''
       and coalesce(trim(v_destino.instituicao), '') <> ''
       and lower(regexp_replace(trim(v_instituicao_time), '\s+', ' ', 'g')) =
           lower(regexp_replace(trim(v_destino.instituicao), '\s+', ' ', 'g')) then
      raise exception 'Conflito institucional na inscrição %.', v_inscricao;
    end if;

    if exists (
      select 1
      from public.avaliacoes a
      where a.environment = p_environment
        and a.inscricao_id_externo = v_inscricao
        and a.parecerista_id_externo = p_parecerista_origem
        and (
          a.concluida
          or coalesce(a.status, 'nao_iniciada') <> 'nao_iniciada'
          or coalesce(trim(a.parecer_geral), '') <> ''
          or coalesce(trim(a.motivo_curta_duracao), '') <> ''
          or exists (
            select 1 from jsonb_array_elements_text(coalesce(a.notas_json, '[]'::jsonb)) as nota(valor)
            where coalesce(trim(valor), '') <> ''
          )
          or exists (
            select 1 from jsonb_array_elements_text(coalesce(a.justificativas_json, '[]'::jsonb)) as justificativa(valor)
            where coalesce(trim(valor), '') <> ''
          )
        )
    ) or exists (
      select 1
      from public.avaliacao_criterios c
      where c.environment = p_environment
        and c.inscricao_id_externo = v_inscricao
        and c.parecerista_id_externo = p_parecerista_origem
        and (coalesce(trim(c.nota), '') <> '' or coalesce(trim(c.justificativa), '') <> '')
    ) then
      raise exception 'A avaliação começou enquanto o lote era preparado (%). Nenhuma alteração foi realizada.', v_inscricao;
    end if;

    update public.atribuicoes
    set ativo = false
    where id = v_atribuicao.id;

    insert into public.atribuicoes (
      environment, inscricao_id_externo, parecerista_id_externo, ordem, origem, ativo
    ) values (
      p_environment, v_inscricao, v_destino_id, v_atribuicao.ordem, 'redistribuicao_pendencias', true
    )
    on conflict (environment, inscricao_id_externo, parecerista_id_externo)
    do update set
      ordem = excluded.ordem,
      origem = 'redistribuicao_pendencias',
      ativo = true;

    insert into public.eventos_auditoria (
      environment, event_type, actor_type, actor_id, inscricao_id,
      parecerista_id, correlation_id, payload_json
    ) values (
      p_environment, 'atribuicao_redistribuida_lote', 'admin', coalesce(nullif(trim(p_actor_id), ''), 'admin'),
      v_inscricao, v_destino_id, v_batch_id || ':' || v_inscricao,
      jsonb_build_object(
        'batch_id', v_batch_id,
        'parecerista_origem', p_parecerista_origem,
        'parecerista_destino', v_destino_id,
        'ordem_preservada', v_atribuicao.ordem
      )
    );
    v_total := v_total + 1;
  end loop;

  insert into public.eventos_auditoria (
    environment, event_type, actor_type, actor_id, correlation_id, payload_json
  ) values (
    p_environment, 'redistribuicao_pendencias_concluida', 'admin',
    coalesce(nullif(trim(p_actor_id), ''), 'admin'), v_batch_id,
    jsonb_build_object(
      'batch_id', v_batch_id,
      'parecerista_origem', p_parecerista_origem,
      'total_movimentos', v_total,
      'destinos_efetivos', v_destinos
    )
  );

  return jsonb_build_object(
    'ok', true,
    'batch_id', v_batch_id,
    'total_movimentos', v_total,
    'destinos_efetivos', v_destinos
  );
end;
$$;

revoke all on function public.redistribuir_atribuicoes_pendentes_segura(text, text, jsonb, text) from public;
grant execute on function public.redistribuir_atribuicoes_pendentes_segura(text, text, jsonb, text) to anon, authenticated;
