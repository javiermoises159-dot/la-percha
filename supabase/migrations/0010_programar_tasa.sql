-- La Percha: (re)programa la tasa BCV ahora que pg_net está activo, y la pide ya.
do $$ begin
  create extension if not exists pg_net;
  perform cron.unschedule(jobid) from cron.job where jobname in ('lapercha_tasa_pedir', 'lapercha_tasa_guardar');
  perform cron.schedule('lapercha_tasa_pedir', '7 * * * *',
    $c$ select net.http_get('https://ve.dolarapi.com/v1/dolares/oficial') $c$);
  perform cron.schedule('lapercha_tasa_guardar', '9 * * * *',
    'select public.tasa_desde_respuesta()');
  perform net.http_get('https://ve.dolarapi.com/v1/dolares/oficial');
exception when others then
  raise notice 'Tasa automática no programada: %', sqlerrm;
end $$;
