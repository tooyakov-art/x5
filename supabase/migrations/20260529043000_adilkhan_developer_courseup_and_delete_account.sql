create or replace function public.is_x5_developer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (auth.jwt() ->> 'email') in (
    'tuakov.ursa@gmail.com',
    'tuakov.ursa@icloud.com',
    'tooyakov.icloud@gmail.com',
    'tooyakov@icloud.com',
    'tooyakov.art@gmail.com',
    'h-a-n-1@mail.ru',
    'adilkhanskii@gmail.com'
  );
$function$;

drop policy if exists "Anyone can create courses" on public.courses;
drop policy if exists "Anyone can update courses" on public.courses;
drop policy if exists "Anyone can delete courses" on public.courses;

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  perform public.x5_delete_eq_if_exists('messages', 'sender_id', uid);
  perform public.x5_delete_eq_if_exists('task_responses', 'specialist_id', uid);
  perform public.x5_delete_eq_if_exists('task_responses', 'client_id', uid);
  perform public.x5_delete_eq_if_exists('tasks', 'author_id', uid);
  perform public.x5_delete_eq_if_exists('portfolio_items', 'user_id', uid);
  perform public.x5_delete_eq_if_exists('specialists', 'user_id', uid);
  perform public.x5_delete_eq_if_exists('push_tokens', 'user_id', uid);
  perform public.x5_delete_eq_if_exists('notification_queue', 'to_user_id', uid);
  perform public.x5_delete_eq_if_exists('notification_queue', 'user_id', uid);
  perform public.x5_delete_eq_if_exists('course_submissions', 'authorId', uid);
  perform public.x5_delete_eq_if_exists('courses', 'author_id', uid);
  perform public.x5_delete_eq_if_exists('courses', 'user_id', uid);
  perform public.x5_delete_eq_if_exists('generation_history', 'user_id', uid);

  begin
    delete from public.followers
    where follower_id = uid or following_id = uid;
  exception
    when undefined_table or undefined_column or undefined_function
      or datatype_mismatch or invalid_text_representation
      or foreign_key_violation then null;
  end;

  begin
    delete from public.chats
    where uid = any(participants);
  exception
    when undefined_table or undefined_column or undefined_function
      or datatype_mismatch or invalid_text_representation
      or foreign_key_violation then
        begin
          delete from public.chats
          where uid::text = any(participants);
        exception
          when undefined_table or undefined_column or undefined_function
            or datatype_mismatch or invalid_text_representation
            or foreign_key_violation then null;
        end;
  end;

  perform public.x5_delete_eq_if_exists('profiles', 'id', uid);

  delete from auth.users where id = uid;
end;
$$;

grant execute on function public.delete_own_account() to authenticated;
