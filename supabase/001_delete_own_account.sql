-- X5: account deletion RPC.
-- Required by App Store Guideline 5.1.1(v).
--
-- HOW TO APPLY:
--   1. Open Supabase Dashboard -> SQL Editor on project afwznqjpshybmqhlewmy
--   2. Paste this entire file and click Run
--   3. Verify with: select proname from pg_proc where proname = 'delete_own_account';

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

  -- Best-effort cleanup of any user-owned rows that may exist in the shared
  -- X5 Marketing Supabase. Each delete is wrapped so a missing table does
  -- not abort the whole transaction.
  begin delete from public.profiles            where id = uid;          exception when undefined_table then null; end;
  begin delete from public.push_tokens         where user_id = uid;     exception when undefined_table then null; end;
  begin delete from public.chats               where uid = any(participants); exception when undefined_table then null; end;
  begin delete from public.messages            where sender_id = uid;   exception when undefined_table then null; end;
  begin delete from public.tasks               where author_id = uid;   exception when undefined_table then null; end;
  begin delete from public.task_responses      where specialist_id = uid; exception when undefined_table then null; end;
  begin delete from public.specialists         where user_id = uid;     exception when undefined_table then null; end;
  begin delete from public.portfolio_items     where user_id = uid;     exception when undefined_table then null; end;
  begin delete from public.followers           where follower_id = uid or following_id = uid; exception when undefined_table then null; end;
  begin delete from public.notification_queue  where to_user_id = uid;  exception when undefined_table then null; end;
  begin delete from public.course_submissions  where "authorId" = uid::text; exception when undefined_table then null; end;

  delete from auth.users where id = uid;
end;
$$;

grant execute on function public.delete_own_account() to authenticated;
