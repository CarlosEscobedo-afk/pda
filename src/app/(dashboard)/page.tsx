import { createClient } from "@/lib/supabase/server";
import { Button } from "@/components/ui/button";
import { GroupGrid } from "@/components/groups/GroupGrid";
import Link from "next/link";
import { Plus, UserPlus } from "lucide-react";

export default async function HomePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: memberships } = await supabase
    .from("group_members")
    .select(
      `
      is_pinned,
      role,
      groups (
        id,
        name,
        emoji,
        category,
        invite_code,
        created_at
      )
    `,
    )
    .eq("user_id", user!.id)
    .order("joined_at", { ascending: false });

  const groups =
    memberships?.flatMap((m) => {
      const g = Array.isArray(m.groups) ? m.groups[0] : m.groups;
      if (!g) return [];
      return [
        {
          id: g.id,
          name: g.name,
          emoji: g.emoji,
          category: g.category,
          is_pinned: m.is_pinned,
          role: m.role,
        },
      ];
    }) ?? [];

  const pinnedGroups = groups.filter((g) => g.is_pinned);
  const otherGroups = groups.filter((g) => !g.is_pinned);

  return (
    <div className="space-y-8">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Mis grupos</h1>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" asChild>
            <Link href="/groups/join">
              <UserPlus className="mr-2 h-4 w-4" />
              Unirme
            </Link>
          </Button>
          <Button size="sm" asChild>
            <Link href="/groups/new">
              <Plus className="mr-2 h-4 w-4" />
              Crear grupo
            </Link>
          </Button>
        </div>
      </div>

      {groups.length === 0 ? (
        <div className="text-center py-16 space-y-4">
          <p className="text-4xl">🤝</p>
          <h2 className="text-xl font-semibold">¡Bienvenido a PDA!</h2>
          <p className="text-muted-foreground max-w-md mx-auto">
            Crea tu primer grupo o únete a uno existente con un código de
            invitación.
          </p>
          <div className="flex gap-3 justify-center">
            <Button asChild>
              <Link href="/groups/new">Crear grupo</Link>
            </Button>
            <Button variant="outline" asChild>
              <Link href="/groups/join">Tengo un código</Link>
            </Button>
          </div>
        </div>
      ) : (
        <>
          {pinnedGroups.length > 0 && (
            <section>
              <h2 className="text-sm font-medium text-muted-foreground mb-3 uppercase tracking-wider">
                Frecuentes
              </h2>
              <GroupGrid groups={pinnedGroups} />
            </section>
          )}

          {otherGroups.length > 0 && (
            <section>
              <h2 className="text-sm font-medium text-muted-foreground mb-3 uppercase tracking-wider">
                {pinnedGroups.length > 0 ? "Otros grupos" : "Todos los grupos"}
              </h2>
              <GroupGrid groups={otherGroups} />
            </section>
          )}
        </>
      )}
    </div>
  );
}
