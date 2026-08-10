-- Quality Audit module (FLU-47): categories/items (admin-editable criteria),
-- visits, item scores, and a simple unweighted scoring view.
--
-- Scoring: intentionally NOT weighted per-item/per-category (client feedback:
-- a 100-point weighted split was "too much"). Overall % = items marked
-- مطابق / items actually scored (لا ينطبق excluded), same 90/80 classification
-- bands as before. If per-section weighting is wanted later, add a
-- weight_pct column then -- don't guess at a scheme preemptively.
--
-- Multi-branch audit access for the two operations managers (FLU-48) is not
-- implemented yet -- for now audit_visits INSERT follows the same
-- admin-or-own-location rule as waste_records, so a branch_manager can only
-- record visits for their own location. Cross-branch access needs FLU-48's
-- role/grant decision first.

create table audit_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table audit_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references audit_categories(id) on delete restrict,
  label text not null,
  definition text,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table audit_visits (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references locations(id),
  auditor_id uuid references profiles(id),
  visit_date date not null default current_date,
  notes text,
  created_at timestamptz not null default now()
);

create table audit_item_scores (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null references audit_visits(id) on delete cascade,
  item_id uuid not null references audit_items(id),
  score smallint check (score in (0, 1)), -- null = لا ينطبق (N/A)
  note text,
  evidence_urls text[],
  created_at timestamptz not null default now(),
  unique (visit_id, item_id)
);

create index audit_items_category_id_idx on audit_items(category_id);
create index audit_visits_location_id_idx on audit_visits(location_id);
create index audit_item_scores_visit_id_idx on audit_item_scores(visit_id);
create index audit_item_scores_item_id_idx on audit_item_scores(item_id);

alter table audit_categories enable row level security;
alter table audit_items enable row level security;
alter table audit_visits enable row level security;
alter table audit_item_scores enable row level security;

-- Criteria tables: everyone can read, only admin can edit -- mirrors
-- lookup_lists/lookup_values exactly, since this is the same
-- "admin-editable reference list" shape.
create policy audit_categories_read on audit_categories
  for select using (true);
create policy audit_categories_admin_write on audit_categories
  for all using (my_role() = 'admin') with check (my_role() = 'admin');

create policy audit_items_read on audit_items
  for select using (true);
create policy audit_items_admin_write on audit_items
  for all using (my_role() = 'admin') with check (my_role() = 'admin');

-- Visit data: same admin-or-own-location shape as waste_records.
create policy audit_visits_select on audit_visits
  for select using (
    my_role() in ('admin', 'accountant') or location_id = my_location()
  );
create policy audit_visits_insert on audit_visits
  for insert with check (
    my_role() = 'admin' or location_id = my_location()
  );

create policy audit_item_scores_select on audit_item_scores
  for select using (
    exists (
      select 1 from audit_visits v
      where v.id = audit_item_scores.visit_id
        and (my_role() in ('admin', 'accountant') or v.location_id = my_location())
    )
  );
create policy audit_item_scores_insert on audit_item_scores
  for insert with check (
    exists (
      select 1 from audit_visits v
      where v.id = audit_item_scores.visit_id
        and (my_role() = 'admin' or v.location_id = my_location())
    )
  );

-- Per-visit score view. security_invoker is required -- see
-- 20260802182849_fix_v_current_stock_security_definer.sql for why the
-- default (security definer) behavior would bypass RLS here too.
create view v_audit_visit_scores
  with (security_invoker = true) as
select
  v.id as visit_id,
  v.location_id,
  v.auditor_id,
  v.visit_date,
  v.notes,
  count(s.id) filter (where s.score is not null) as items_scored,
  count(s.id) filter (where s.score = 1) as items_passed,
  count(s.id) filter (where s.score = 0) as items_failed,
  case
    when count(s.id) filter (where s.score is not null) = 0 then null
    else round(
      100.0 * count(s.id) filter (where s.score = 1)
        / count(s.id) filter (where s.score is not null),
      1
    )
  end as overall_pct,
  case
    when count(s.id) filter (where s.score is not null) = 0 then null
    when 100.0 * count(s.id) filter (where s.score = 1)
      / count(s.id) filter (where s.score is not null) >= 90 then 'ممتاز'
    when 100.0 * count(s.id) filter (where s.score = 1)
      / count(s.id) filter (where s.score is not null) >= 80 then 'يحتاج تحسين'
    else 'يحتاج تدخل إداري'
  end as classification
from audit_visits v
left join audit_item_scores s on s.visit_id = v.id
group by v.id;

-- Records a full visit (header + all item scores) in one call, mirroring
-- record_waste's security-definer + explicit role/location check shape.
create or replace function record_audit_visit(
  p_location_id uuid,
  p_visit_date date,
  p_notes text,
  p_scores jsonb -- [{"item_id": "...", "score": 0|1|null, "note": "...", "evidence_urls": ["..."]}]
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_visit_id uuid;
begin
  if not coalesce(
    my_role() = 'admin' or p_location_id = my_location(),
    false
  ) then
    raise exception 'not authorized to record an audit visit for this location';
  end if;

  insert into audit_visits (location_id, auditor_id, visit_date, notes)
  values (p_location_id, auth.uid(), coalesce(p_visit_date, current_date), p_notes)
  returning id into v_visit_id;

  insert into audit_item_scores (visit_id, item_id, score, note, evidence_urls)
  select
    v_visit_id,
    (elem->>'item_id')::uuid,
    nullif(elem->>'score', '')::smallint,
    elem->>'note',
    case
      when elem->'evidence_urls' is null then null
      else array(select jsonb_array_elements_text(elem->'evidence_urls'))
    end
  from jsonb_array_elements(coalesce(p_scores, '[]'::jsonb)) as elem;

  return v_visit_id;
end;
$$;

with cat as (
  insert into audit_categories (name, sort_order) values
    ('المواد المرجعية والالتزامات القانونية', 0),
    ('منطقة الكاشير', 1),
    ('التعامل مع المنتجات / جودة الطعام', 2),
    ('منطقة المطبخ', 3),
    ('منطقة الزبائن (الصالة)', 4),
    ('أداء الموظفين', 5),
    ('الحمامات والمنطقة الخارجية', 6),
    ('خطة العمل ومتابعة الزيارات السابقة', 7)
  returning id, name
)
insert into audit_items (category_id, label, definition, sort_order)
select cat.id, v.label, v.definition, v.sort_order
from (values
    ('المواد المرجعية والالتزامات القانونية', 'دليل ساندويشات فلافي برجر متوفر', 'النسخة المعتمدة من دليل الساندويشات متوفرة وحديثة في الفرع.', 0),
    ('المواد المرجعية والالتزامات القانونية', 'لائحة تفقد درجات الحرارة معلّقة ومستخدمة', 'سجل درجات الحرارة اليومي معلّق في مكانه ومعبأ بانتظام.', 1),
    ('المواد المرجعية والالتزامات القانونية', 'مقياس الحرارة متوفر وفعّال', 'يوجد ثيرمومتر معايَر يعمل بشكل صحيح في كل نقطة تحتاجه.', 2),
    ('المواد المرجعية والالتزامات القانونية', 'التنبيهات التشغيلية متوفرة وموقّعة (أوقات الطهي)', 'لوحات أوقات الطهي/التحضير المعتمدة معلّقة وموقّعة من المسؤول.', 3),
    ('المواد المرجعية والالتزامات القانونية', 'شهادات صحية سارية لكل موظف', 'كل موظف يحمل شهادة صحية سارية المفعول.', 4),
    ('المواد المرجعية والالتزامات القانونية', 'ترخيص المطعم والسجل التجاري متوفران وساريان', 'الوثائق الرسمية معلّقة أو متوفرة ومحدّثة.', 5),
    ('المواد المرجعية والالتزامات القانونية', 'لائحة ترتيب المواد الغذائية داخل الثلاجة متوفرة', 'دليل مرجعي لترتيب التخزين معلّق بجانب كل ثلاجة.', 6),
    ('منطقة الكاشير', 'اتّباع خطوات أخذ الطلبات بشكل صحيح', 'موظف المبيعات يتبع الخطوات المعتمدة عند استقبال الطلب.', 7),
    ('منطقة الكاشير', 'معرفة موظف المبيعات الكافية بقائمة الطعام', 'قادر على الإجابة عن مكونات وأسعار الأصناف دون تردد.', 8),
    ('منطقة الكاشير', 'الرد السريع على مكالمات الهاتف', 'لا يوجد تأخير ملحوظ في الرد على الاتصالات أثناء الزيارة.', 9),
    ('منطقة الكاشير', 'التعامل اللائق والسريع مع الزبائن', 'ملاحَظ خلال الزيارة تعامل مهذب وسريع مع العملاء.', 10),
    ('منطقة الكاشير', 'كفاية أعداد موظفي المبيعات وقت الذروة', 'لا يوجد نقص واضح بالكوادر أثناء أوقات الذروة.', 11),
    ('منطقة الكاشير', 'تشجيع رفع تقييم المطعم على جوجل', 'الموظفون يطلبون من العملاء تقييم الفرع على جوجل.', 12),
    ('منطقة الكاشير', 'توفر QR Code للمنيو/التقييم', 'الرمز ظاهر وقابل للمسح وموجّه للصفحة الصحيحة.', 13),
    ('منطقة الكاشير', 'معرفة موظف المبيعات بتقنيات البيع', 'يقترح إضافات أو أصناف تكميلية للعميل بشكل استباقي (Upselling).', 14),
    ('منطقة الكاشير', 'عدم وجود فروقات نقدية غير مبررة بالصندوق', 'رصيد الكاشير الفعلي يطابق النظام دون فروقات غير موثقة.', 15),
    ('منطقة الكاشير', 'تطبيق إجراءات الافتتاح والإغلاق', 'قائمة تحقق الافتتاح/الإغلاق موقّعة ومكتملة لليوم أو لآخر يوم عمل.', 16),
    ('التعامل مع المنتجات / جودة الطعام', 'تجهيز وحفظ الخبز بشكل صحيح', 'محفوظ في العبوة الأصلية بعيداً عن الرطوبة والحرارة، ويُستخدم ضمن مدة الصلاحية بعد الفتح.', 17),
    ('التعامل مع المنتجات / جودة الطعام', 'إذابة وحفظ الأطعمة المجمّدة بشكل صحيح', 'تتم الإذابة داخل الثلاجة أو بالطريقة المعتمدة، وليس على سطح العمل أو بالماء الساخن.', 18),
    ('التعامل مع المنتجات / جودة الطعام', 'حفظ التوابل/المكوّنات المفتوحة والمحضّرة بشكل صحيح', 'مؤرَّخة ومغطاة ومخزَّنة ضمن درجة الحرارة المطلوبة.', 19),
    ('التعامل مع المنتجات / جودة الطعام', 'اتّباع نظام تخزين صحيح داخل الثلاجة', 'المواد النيئة أسفل الجاهزة، ولا تجاور مواد التنظيف الطعام.', 20),
    ('التعامل مع المنتجات / جودة الطعام', 'الالتزام بالأوزان والمكوّنات الصحيحة للساندويشات والأطباق', 'تطابق بطاقة الوصفة المعتمدة عند الفحص العشوائي.', 21),
    ('التعامل مع المنتجات / جودة الطعام', 'طهي وحفظ وتحضير البطاطا المقلية بشكل صحيح', 'درجة الحرارة والوقت ضمن المعيار، ولا تُترك خارج الفريزر لفترات طويلة.', 22),
    ('التعامل مع المنتجات / جودة الطعام', 'طهي الدجاج المقلي بشكل صحيح', 'درجة حرارة داخلية آمنة ووقت طهي مطابق للمعيار.', 23),
    ('التعامل مع المنتجات / جودة الطعام', 'إعداد الصوص وفق المعيار التشغيلي المعتمد', 'يُحضَّر بالمقادير والخطوات المعتمدة، ومؤرَّخ.', 24),
    ('التعامل مع المنتجات / جودة الطعام', 'إعداد وطهي صوص الجبن السائل وفق المعيار', 'يُحضَّر ويُحفَظ بالطريقة ودرجة الحرارة المعتمدة.', 25),
    ('التعامل مع المنتجات / جودة الطعام', 'تقديم الطعام للزبائن ساخناً', 'درجة حرارة التقديم ضمن الحد الأدنى المعتمد وقت التسليم للزبون.', 26),
    ('التعامل مع المنتجات / جودة الطعام', 'عدم إذابة منتجات خارج الثلاجات المخصصة', 'لا يوجد صنف يُذاب على سطح العمل أو خارج المكان المخصص وقت الزيارة.', 27),
    ('التعامل مع المنتجات / جودة الطعام', 'تطبيق FIFO/FEFO وتواريخ الصلاحية سليمة', 'لا يوجد صنف منتهي الصلاحية على الرفوف أو في الثلاجة، والأقدم يُستخدم أولاً.', 28),
    ('منطقة المطبخ', 'درجة حرارة المعدات ضمن المستوى القياسي', 'ضمن النطاق القياسي المعتمد لكل جهاز.', 29),
    ('منطقة المطبخ', 'درجة حرارة المنتجات الغذائية ضمن المستوى القياسي', 'ضمن النطاق الآمن المعتمد وقت الفحص.', 30),
    ('منطقة المطبخ', 'اتّباع نظام ترتيب المواد الغذائية داخل الثلاجة', 'يتبع اللائحة المعتمدة (نيء أسفل جاهز، حسب الصلاحية).', 31),
    ('منطقة المطبخ', 'تواجد الموظفين الكافي وقت الذروة', 'عدد كافٍ من الموظفين في محطات العمل خلال ساعات الذروة.', 32),
    ('منطقة المطبخ', 'عدم وجود مواد أولية غير معتمدة', 'لا يوجد أي منتج من مورد غير معتمد من الشركة.', 33),
    ('منطقة المطبخ', 'عدم وجود نقص بالمواد الأولية', 'لا يوجد صنف رئيسي غير متوفر وقت الزيارة.', 34),
    ('منطقة المطبخ', 'جميع الأجهزة متوفرة وتعمل بصورة سليمة', 'أجهزة المطبخ (قلايات، أفران، ثلاجات) تعمل دون أعطال.', 35),
    ('منطقة المطبخ', 'التزام الموظفين بتنظيف منطقة القلي', 'الزيت والقلاية نظيفان وخاليان من التراكمات.', 36),
    ('منطقة المطبخ', 'التزام الموظفين بتنظيف منطقة تحضير الساندويشات', 'التوستر وطاولة التحضير والثلاجات نظيفة وخالية من البقايا.', 37),
    ('منطقة المطبخ', 'التزام الموظفين بتنظيف منطقة تحضير الأطباق الجانبية والبطاطا', 'أدوات ومساحة تحضير البطاطا نظيفة.', 38),
    ('منطقة المطبخ', 'عمل الساحبة الهوائية ودرجة حرارة المطبخ مناسبة', 'التهوية تعمل ودرجة الحرارة مناسبة للعمل.', 39),
    ('منطقة المطبخ', 'نظافة منطقة المجلى', 'المجلى والأرفف والأرضية خالية من تراكم الأوساخ.', 40),
    ('منطقة المطبخ', 'نسبة الهدر ضمن المستهدف', 'نسبة الهدر المسجلة للفترة الحالية لا تتجاوز الهدف المعتمد (مثال: 2%).', 41),
    ('منطقة المطبخ', 'مطابقة الجرد الفعلي مع النظام', 'الفرق بين الجرد الفعلي والرصيد في النظام لا يتجاوز الحد المسموح (مثال: 3%).', 42),
    ('منطقة الزبائن (الصالة)', 'نظافة أرضية الصالة', 'خالية من البقع والانسكابات والفتات.', 43),
    ('منطقة الزبائن (الصالة)', 'نظافة جدران الصالة', 'خالية من الغبار والبقع الظاهرة.', 44),
    ('منطقة الزبائن (الصالة)', 'نظافة التحف والأرفف', 'خالية من الغبار المتراكم.', 45),
    ('منطقة الزبائن (الصالة)', 'نظافة الزجاج', 'لامع وخالٍ من البصمات والبقع.', 46),
    ('منطقة الزبائن (الصالة)', 'نظافة الطاولات', 'خالية من البقع والفتات بين كل عميل وآخر.', 47),
    ('منطقة الزبائن (الصالة)', 'نظافة الكراسي', 'خالية من الاتساخ وسليمة هيكلياً.', 48),
    ('منطقة الزبائن (الصالة)', 'نظافة علب المناديل (الفاين)', 'نظيفة وممتلئة.', 49),
    ('منطقة الزبائن (الصالة)', 'نظافة علب الصوص', 'نظيفة من الخارج وخالية من التصاق الصوص القديم.', 50),
    ('منطقة الزبائن (الصالة)', 'توافر شاشات العرض وعملها بشكل صحيح', 'تعمل وتعرض المحتوى المعتمد.', 51),
    ('منطقة الزبائن (الصالة)', 'عمل نظام الموسيقى وفق سياسة الشركة', 'يعمل وفق قائمة التشغيل المعتمدة.', 52),
    ('منطقة الزبائن (الصالة)', 'توفر الصوصات بكميات مناسبة', 'مخزَّنة داخل الثلاجة المخصصة وليس خارجها.', 53),
    ('منطقة الزبائن (الصالة)', 'توفر الفاين داخل العلب المخصصة له', 'لا يوجد تخزين عشوائي خارج مكانه.', 54),
    ('منطقة الزبائن (الصالة)', 'عمل الساحبة الهوائية ودرجة حرارة الصالة مناسبة', 'التهوية تعمل والصالة بدرجة حرارة مريحة للعملاء.', 55),
    ('منطقة الزبائن (الصالة)', 'عدم تقديم وجبات من علامة تجارية أخرى', 'القائمة المقدَّمة تقتصر على منتجات فلافي برجر المعتمدة.', 56),
    ('أداء الموظفين', 'الالتزام بسياسة الزي الموحد والنظافة الشخصية', 'جميع الموظفين، بمن فيهم الإدارة والكاشير، ملتزمون بالزي الكامل والنظافة الشخصية.', 57),
    ('أداء الموظفين', 'استخدام الأدوات والمواد الكيميائية بشكل صحيح', 'تُستخدم وفق التعليمات وتُخزَّن بأمان بعيداً عن الطعام.', 58),
    ('أداء الموظفين', 'معرفة الموظفين بمهام التنظيف وإكمالها', 'يعرفون مهامهم المخصصة وأكملوها وفق الجدول.', 59),
    ('أداء الموظفين', 'معرفة المدراء والموظفين بالعروض الترويجية الحالية', 'قادرون على شرح العروض الحالية للزبائن.', 60),
    ('أداء الموظفين', 'الالتزام بإجراءات غسيل المعدات الصغيرة', 'يتبع خطوات الغسيل والتعقيم المعتمدة.', 61),
    ('أداء الموظفين', 'متابعة المدير المسؤول لإجراءات الطهي', 'المدير يراقب ويصحح إجراءات الطهي أثناء المناوبة.', 62),
    ('أداء الموظفين', 'الالتزام بارتداء القفازات في جميع أوقات العمل', 'إلزامي في جميع أوقات التحضير والتقديم.', 63),
    ('أداء الموظفين', 'الالتزام بإجراءات حفظ جودة المنتجات', 'تُطبَّق بشكل متسق لمنع التلف والهدر.', 64),
    ('أداء الموظفين', 'عدم تقديم وجبات غير مذكورة بالمنيو', 'الفرع لا يبيع أصنافاً خارج القائمة المعتمدة.', 65),
    ('أداء الموظفين', 'اتّباع موظفي الصالة خطوات التعامل الصحيح مع الزبائن', 'يتبعون خطوات الاستقبال والخدمة المعتمدة.', 66),
    ('أداء الموظفين', 'تقديم المدير دعماً وتغذية راجعة تصحيحية خلال المناوبة', 'يقدّم توجيهاً تصحيحياً فورياً عند الحاجة.', 67),
    ('أداء الموظفين', 'سرعة تجهيز الطعام بالوقت المطلوب', 'ضمن الوقت المستهدف المعتمد.', 68),
    ('أداء الموظفين', 'قيام المدير بتحفيز الفريق عند الحاجة', 'يظهر تقديراً أو تحفيزاً ملموساً للموظفين المتميزين.', 69),
    ('أداء الموظفين', 'أخذ المدير لانطباعات العملاء بانتظام', 'يتفاعل مع الزبائن ويسأل عن تجربتهم بانتظام.', 70),
    ('أداء الموظفين', 'الطريقة الصحيحة لإعداد الساندويشات', 'تتبع خطوات التجميع المعتمدة (الترتيب، الكمية، الغلاف).', 71),
    ('أداء الموظفين', 'الحضور والانضباط والجدول مكتمل', 'لا غياب غير مبرر، والجدول مكتمل بالعدد المطلوب للوردية وقت الزيارة.', 72),
    ('أداء الموظفين', 'لا توجد شكاوى متكررة على أداء موظف', 'لا يوجد موظف واحد عليه أكثر من شكوى موثقة واحدة خلال آخر 30 يوماً.', 73),
    ('الحمامات والمنطقة الخارجية', 'نظافة الحمامات', 'الأرضية والجدران والسقف والمقعد والمرآة والمغسلة نظيفة، والصابون متوفر، ولا روائح كريهة.', 74),
    ('الحمامات والمنطقة الخارجية', 'خلوّ المنطقة المحيطة من تخزين البضائع', 'لا يوجد تخزين عشوائي للمواد الأولية أو الكيميائية أو الورقيات في الخارج.', 75),
    ('الحمامات والمنطقة الخارجية', 'نظافة المنطقة المحيطة', 'خالية من تراكم الزيوت والكراتين والنفايات.', 76),
    ('الحمامات والمنطقة الخارجية', 'نظافة المدخل', 'خالٍ من تراكم الأوساخ والنفايات عند الباب الرئيسي.', 77),
    ('خطة العمل ومتابعة الزيارات السابقة', 'اكتمال خطة عمل الزيارة الحالية', 'جميع بنود هذه الزيارة التي تحتاج إجراء تم تسجيلها في سجل الإجراءات التصحيحية.', 78),
    ('خطة العمل ومتابعة الزيارات السابقة', 'اكتمال خطة عمل الزيارة السابقة', 'جميع الإجراءات التصحيحية من الزيارة السابقة تم إغلاقها أو لها متابعة نشطة.', 79)
) as v(cat_name, label, definition, sort_order)
join cat on cat.name = v.cat_name;
