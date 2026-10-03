-- Roast pawns becomes the default design.
alter table public.profiles
  drop constraint profiles_design_check,
  add constraint profiles_design_check
    check (design in ('pawns', 'chalkboard', 'receipt', 'crema', 'bauhaus', 'sunrise')),
  alter column design set default 'pawns';
