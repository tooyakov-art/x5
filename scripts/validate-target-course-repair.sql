begin;

do $repair_validation$
declare
  v_target_id uuid := '892fc2d1-f521-48a2-800f-a90eb9e1a852'::uuid;
  v_before jsonb;
  v_after jsonb;
  v_recovered_module jsonb;
  v_author text;
  v_hidden_count integer;
begin
  select categories, author_name
  into v_before, v_author
  from public.courses
  where id = v_target_id
  for update;

  if v_before is null then
    raise exception 'target_course_missing';
  end if;

  select category
  into v_recovered_module
  from public.courses as source_course
  cross join lateral jsonb_array_elements(coalesce(source_course.categories, '[]'::jsonb)) as source_category(category)
  where source_course.title = U&'\041D\043E\0432\044B\0439\0020\043A\0443\0440\0441'
    and source_category.category ->> 'title' = U&'\041E\0441\043D\043E\0432\044B\0020\0442\0430\0440\0433\0435\0442\0430'
  order by source_course.created_at, source_course.id
  limit 1;

  if v_recovered_module is null then
    raise exception 'recovery_module_missing';
  end if;

  update public.courses
  set categories = jsonb_build_array(v_recovered_module) || v_before,
      updated_at = now()
  where id = v_target_id;

  update public.courses as duplicate
  set is_public = false,
      updated_at = now()
  where duplicate.title = U&'\041D\043E\0432\044B\0439\0020\043A\0443\0440\0441'
    and exists (
      select 1
      from jsonb_array_elements(coalesce(duplicate.categories, '[]'::jsonb)) as category
      where category ->> 'title' = U&'\041E\0441\043D\043E\0432\044B\0020\0442\0430\0440\0433\0435\0442\0430'
    );

  select categories
  into v_after
  from public.courses
  where id = v_target_id;

  if jsonb_array_length(v_after) <> jsonb_array_length(v_before) + 1 then
    raise exception 'unexpected_category_count';
  end if;

  if v_after -> 1 is distinct from v_before -> 0 then
    raise exception 'existing_module_changed';
  end if;

  if (select author_name from public.courses where id = v_target_id) is distinct from v_author then
    raise exception 'author_changed';
  end if;

  select count(*)
  into v_hidden_count
  from public.courses as duplicate
  where duplicate.title = U&'\041D\043E\0432\044B\0439\0020\043A\0443\0440\0441'
    and duplicate.is_public = false
    and exists (
      select 1
      from jsonb_array_elements(coalesce(duplicate.categories, '[]'::jsonb)) as category
      where category ->> 'title' = U&'\041E\0441\043D\043E\0432\044B\0020\0442\0430\0440\0433\0435\0442\0430'
    );

  if v_hidden_count <> 3 then
    raise exception 'unexpected_hidden_duplicate_count:%', v_hidden_count;
  end if;
end;
$repair_validation$;

rollback;

select 'validated_with_rollback' as status;
