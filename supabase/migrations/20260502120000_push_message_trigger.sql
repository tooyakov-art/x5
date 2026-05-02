-- Push notification trigger for chat messages.
-- Posts the new message row to the send-message-push Edge Function via pg_net.
-- The function looks up the recipient's push_token and sends an APNs payload.

create extension if not exists pg_net;

create or replace function notify_new_message() returns trigger
language plpgsql security definer as $$
begin
  perform net.http_post(
    url := 'https://afwznqjpshybmqhlewmy.functions.supabase.co/send-message-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := to_jsonb(NEW)
  );
  return NEW;
end;
$$;

drop trigger if exists messages_push_notify on messages;
create trigger messages_push_notify after insert on messages
  for each row execute function notify_new_message();
