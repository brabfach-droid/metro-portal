-- Запустіть один раз у Supabase SQL Editor у новому проєкті.
create extension if not exists pgcrypto;
create table if not exists public.admin_users (user_id uuid primary key references auth.users(id) on delete cascade, created_at timestamptz not null default now());
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$ select exists(select 1 from public.admin_users where user_id = (select auth.uid())) $$;
revoke all on function public.is_admin() from public; grant execute on function public.is_admin() to anon, authenticated;
create table if not exists public.categories (id uuid primary key default gen_random_uuid(), kind text not null check(kind in ('news','documents','announcements','files')), name text not null, position int not null default 0, unique(kind,name));
create table if not exists public.news (id uuid primary key default gen_random_uuid(), title text not null, summary text not null default '', body text not null default '', category_id uuid references public.categories(id) on delete set null, author text not null default '', published_at date, pinned boolean not null default false, cover_path text, gallery_paths text[] not null default '{}', status text not null default 'draft' check(status in ('draft','published','archived')), deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists public.documents (id uuid primary key default gen_random_uuid(), title text not null, document_number text not null default '', document_date date, year int generated always as (extract(year from document_date)::int) stored, category_id uuid references public.categories(id) on delete set null, description text not null default '', pdf_path text, status text not null default 'draft' check(status in ('draft','published','archived')), deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists public.announcements (id uuid primary key default gen_random_uuid(), title text not null, body text not null default '', announcement_date date, category_id uuid references public.categories(id) on delete set null, important boolean not null default false, status text not null default 'draft' check(status in ('draft','published','archived')), deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists public.files (id uuid primary key default gen_random_uuid(), title text not null, description text not null default '', category_id uuid references public.categories(id) on delete set null, file_date date, size_bytes bigint, storage_path text, status text not null default 'draft' check(status in ('draft','published','archived')), deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists public.media (id uuid primary key default gen_random_uuid(), title text not null, description text not null default '', storage_path text, status text not null default 'draft' check(status in ('draft','published','archived')), deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists public.management (id uuid primary key default gen_random_uuid(), name text not null default '', role text not null default '', photo_path text, position int not null default 0, visible boolean not null default true, deleted_at timestamptz, created_at timestamptz not null default now());
create table if not exists public.site_settings (id int primary key default 1 check(id=1), site_name text not null default 'КП «Голосіївський метрополітен»', site_description text not null default 'Офіційний інформаційний портал підприємства', contact_address text not null default '', contact_phone text not null default '', contact_email text not null default '', alert_enabled boolean not null default false, alert_title text not null default 'Важливе повідомлення', alert_text text not null default '', alert_link text not null default '', depot_status text not null default '', depot_description text not null default '', about_text text not null default '', infrastructure_text text not null default '', updated_at timestamptz not null default now());
create table if not exists public.activity_log (id bigint generated always as identity primary key, actor_id uuid references auth.users(id) on delete set null, action text not null, entity_type text not null, entity_id uuid, created_at timestamptz not null default now());
insert into public.site_settings(id) values (1) on conflict (id) do nothing;
insert into public.categories(kind,name,position) values ('documents','Накази',1),('documents','Проєктна документація',2),('documents','Технічна документація',3),('documents','Організаційні документи',4),('documents','Інші матеріали',5) on conflict(kind,name) do nothing;
insert into public.management(name,role,position) select 'Сергій Вікторович Берестов','Директор',1 where not exists(select 1 from public.management where role='Директор');

alter table public.admin_users enable row level security;
create policy "admin identity" on public.admin_users for select to authenticated using (user_id = (select auth.uid()));

-- Публіка бачить тільки опубліковані матеріали; адміністратор бачить усе.
do $$ declare t text; begin
  foreach t in array array['news','documents','announcements','files','media'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('create policy "public published" on public.%I for select to anon, authenticated using ((status = ''published'' and deleted_at is null) or (select public.is_admin()))',t);
    execute format('create policy "admin insert" on public.%I for insert to authenticated with check ((select public.is_admin()))',t);
    execute format('create policy "admin update" on public.%I for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()))',t);
    execute format('create policy "admin delete" on public.%I for delete to authenticated using ((select public.is_admin()))',t);
  end loop;
end $$;
alter table public.categories enable row level security;
create policy "categories read" on public.categories for select to anon, authenticated using (true);
create policy "categories admin insert" on public.categories for insert to authenticated with check ((select public.is_admin()));
create policy "categories admin update" on public.categories for update to authenticated using ((select public.is_admin()));
create policy "categories admin delete" on public.categories for delete to authenticated using ((select public.is_admin()));
alter table public.management enable row level security;
create policy "management read" on public.management for select to anon, authenticated using ((visible and deleted_at is null) or (select public.is_admin()));
create policy "management insert" on public.management for insert to authenticated with check ((select public.is_admin()));
create policy "management update" on public.management for update to authenticated using ((select public.is_admin()));
create policy "management delete" on public.management for delete to authenticated using ((select public.is_admin()));
alter table public.site_settings enable row level security;
create policy "settings read" on public.site_settings for select to anon, authenticated using (true);
create policy "settings update" on public.site_settings for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
alter table public.activity_log enable row level security;
create policy "log read" on public.activity_log for select to authenticated using ((select public.is_admin()));
create policy "log insert" on public.activity_log for insert to authenticated with check ((select public.is_admin()) and actor_id=(select auth.uid()));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
('documents','documents',false,52428800,array['application/pdf']),
('photos','photos',false,15728640,array['image/jpeg','image/png','image/webp']),
('downloads','downloads',false,104857600,array['application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/zip','image/jpeg','image/png','image/webp','text/plain'])
on conflict (id) do update set public=false, file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;
create policy "storage authenticated public references" on storage.objects for select to anon,authenticated using (
  (bucket_id='documents' and exists(select 1 from public.documents d where d.pdf_path=name and d.status='published' and d.deleted_at is null)) or
  (bucket_id='photos' and (exists(select 1 from public.media m where m.storage_path=name and m.status='published' and m.deleted_at is null) or exists(select 1 from public.news n where n.status='published' and n.deleted_at is null and (n.cover_path=name or name=any(n.gallery_paths))) or exists(select 1 from public.management g where g.photo_path=name and g.visible and g.deleted_at is null))) or
  (bucket_id='downloads' and exists(select 1 from public.files f where f.storage_path=name and f.status='published' and f.deleted_at is null)) or (select public.is_admin())
);
create policy "storage admin upload" on storage.objects for insert to authenticated with check (bucket_id in ('documents','photos','downloads') and (select public.is_admin()));
create policy "storage admin update" on storage.objects for update to authenticated using (bucket_id in ('documents','photos','downloads') and (select public.is_admin())) with check (bucket_id in ('documents','photos','downloads') and (select public.is_admin()));
create policy "storage admin delete" on storage.objects for delete to authenticated using (bucket_id in ('documents','photos','downloads') and (select public.is_admin()));
create index if not exists news_public_idx on public.news(status,deleted_at,published_at desc);
create index if not exists documents_public_idx on public.documents(status,deleted_at,document_date desc);
create index if not exists announcements_public_idx on public.announcements(status,deleted_at,announcement_date desc);
