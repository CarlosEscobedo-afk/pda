"use client";

import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Pin } from "lucide-react";
import Link from "next/link";
import { string } from "zod";

const categoryLabels: Record<string, string> = {
  domestic: "Doméstico",
  social: "Social",
  travel: "Viaje",
  roommates: "Roommates",
  project: "Proyecto",
  sports: "Deportes",
  savings: "Ahorro",
  pets: "Mascotas",
  events: "Evento",
  custom: "Personalizado",
};

interface GroupCardProps {
  group: {
    id: string;
    name: string;
    emoji: string;
    category: string;
    is_pinned: boolean;
    role: string;
  };
}

export function GroupCard({ group }: GroupCardProps) {
  return (
    <Link href={`/groups/${group.id}`}>
      <Card className="hover:bg-accent/50 transition-colors cursor-pointer h-full">
        <CardHeader className="pb-3">
          <div className="flex items-start justify-between">
            <div className="flex items-center gap-3">
              <span className="text-2xl">{group.emoji}</span>
              <div>
                <CardTitle className="text-base">{group.name}</CardTitle>
                <CardDescription className="text-xs mt-0.5">
                  {categoryLabels[group.category] ?? group.category}
                </CardDescription>
              </div>
            </div>
            <div className="flex items-center gap-1.5">
              {group.is_pinned && (
                <Pin className="h-3.5 w-3.5 text-muted-foreground" />
              )}
              {group.role === "admin" && (
                <Badge variant="secondary" className="text-[10px] px-1.5">
                  Admin
                </Badge>
              )}
            </div>
          </div>
        </CardHeader>
      </Card>
    </Link>
  );
}
