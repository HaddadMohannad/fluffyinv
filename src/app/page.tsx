import { getCurrentUser } from "@/lib/auth/session";
import { signOut } from "@/app/actions/auth";

export default async function Home() {
  const currentUser = await getCurrentUser();

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 bg-white px-6 text-center dark:bg-black">
      <h1 className="text-fluffy-dark text-3xl font-semibold tracking-tight dark:text-zinc-50">
        Fluffy Inventory
      </h1>
      {currentUser?.profile ? (
        <p className="max-w-md text-base text-zinc-600 dark:text-zinc-400">
          Signed in as {currentUser.profile.full_name} —{" "}
          <span className="font-medium">{currentUser.profile.role}</span>
          {currentUser.location ? ` · ${currentUser.location.name_en}` : ""}
        </p>
      ) : (
        <p className="max-w-md text-base text-zinc-600 dark:text-zinc-400">
          Signed in as {currentUser?.email}, but no profile record exists for
          this account yet — ask an admin to create one.
        </p>
      )}
      <form action={signOut}>
        <button
          type="submit"
          className="h-11 rounded-md border border-zinc-300 px-5 text-base font-medium dark:border-zinc-700"
        >
          Sign out
        </button>
      </form>
      <span className="bg-fluffy-orange inline-block h-2 w-16 rounded-full" />
    </div>
  );
}
