import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";

export function HomePage() {
  const { session, profile, location } = useAuth();
  const { t } = useLocale();

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 bg-white px-6 text-center dark:bg-black">
      <h1 className="text-fluffy-dark text-3xl font-semibold tracking-tight dark:text-zinc-50">
        {t.appName}
      </h1>
      {profile ? (
        <p className="max-w-md text-base text-zinc-600 dark:text-zinc-400">
          {profile.full_name} —{" "}
          <span className="font-medium">{profile.role}</span>
          {location ? ` · ${location.name_en}` : ""}
        </p>
      ) : (
        <p className="max-w-md text-base text-zinc-600 dark:text-zinc-400">
          {session?.user.email}: {t.noProfile}
        </p>
      )}
      <span className="bg-fluffy-orange inline-block h-2 w-16 rounded-full" />
    </div>
  );
}
