create or replace function public.is_x5_developer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (auth.jwt() ->> 'email') in (
    'tuakov.ursa@gmail.com',
    'tooyakov.icloud@gmail.com',
    'tooyakov@icloud.com',
    'tooyakov.art@gmail.com',
    'h-a-n-1@mail.ru',
    'adilkhanskii@gmail.com'
  );
$function$;
