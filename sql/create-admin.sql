-- Спершу створіть користувача в Authentication → Users → Add user.
-- Замініть UUID_FROM_AUTH_USERS його точним UUID. Не вставляйте пароль у SQL.
-- Логін admin у формі відповідає технічному email admin@metro.example.invalid.
insert into public.admin_users(user_id)
values ('UUID_FROM_AUTH_USERS');
