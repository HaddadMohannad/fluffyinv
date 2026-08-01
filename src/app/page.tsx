export default function Home() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 bg-white px-6 text-center dark:bg-black">
      <h1 className="text-fluffy-dark text-3xl font-semibold tracking-tight dark:text-zinc-50">
        Fluffy Inventory
      </h1>
      <p className="max-w-md text-base text-zinc-600 dark:text-zinc-400">
        App foundation scaffold is up. Feature screens land in later epics.
      </p>
      <span className="bg-fluffy-orange inline-block h-2 w-16 rounded-full" />
    </div>
  );
}
