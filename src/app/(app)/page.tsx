import { getCurrentUser } from "@/lib/auth/session";
import { getLocale } from "@/lib/i18n/locale";
import { dictionary } from "@/lib/i18n/dictionary";

export default async function Home() {
  const [currentUser, locale] = await Promise.all([
    getCurrentUser(),
    getLocale(),
  ]);
  const t = dictionary[locale];

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 bg-white px-6 text-center dark:bg-black">
      <h1 className="text-fluffy-dark text-3xl font-semibold tracking-tight dark:text-zinc-50">
        {t.appName}
      </h1>
      {currentUser?.profile ? (
        <p className="max-w-md text-base text-zinc-600 dark:text-zinc-400">
          {currentUser.profile.full_name} —{" "}
          <span className="font-medium">{currentUser.profile.role}</span>
          {currentUser.location ? ` · ${currentUser.location.name_en}` : ""}
        </p>
      ) : (
        <p className="max-w-md text-base text-zinc-600 dark:text-zinc-400">
          {t.noProfile}
        </p>
      )}
      <span className="bg-fluffy-orange inline-block h-2 w-16 rounded-full" />
    </div>
  );
}
