import { GroupCard } from "./GroupCard";

interface Group {
  id: string;
  name: string;
  emoji: string;
  category: string;
  is_pinned: boolean;
  role: string;
}

export function GroupGrid({ groups }: { groups: Group[] }) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
      {groups.map((group) => (
        <GroupCard key={group.id} group={group} />
      ))}
    </div>
  );
}
