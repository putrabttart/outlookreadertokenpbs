import type { InboxMessage } from "./graph"

export interface EmailFilterSettings {
    enabled: boolean
    description: string
    sender: string
    subjectContains: string
    bodyContains: string
}

export const defaultEmailFilterSettings: EmailFilterSettings = {
    enabled: false,
    description: "",
    // Sender is intentionally blank for local testing because forwarded mail
    // may no longer have the original Netflix sender address.
    sender: "",
    subjectContains: "Kode akses sementara Netflix-mu",
    bodyContains: "kode akses sementara",
}

function includesIgnoreCase(value: string, query: string): boolean {
    return value.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())
}

export function matchesEmailFilter(message: InboxMessage, settings: EmailFilterSettings): boolean {
    if (!settings.enabled) return true
    if (settings.sender.trim() && !includesIgnoreCase(message.from, settings.sender)) return false
    if (settings.subjectContains.trim() && !includesIgnoreCase(message.subject, settings.subjectContains)) return false
    if (settings.bodyContains.trim() && !includesIgnoreCase(message.bodyPreview, settings.bodyContains)) return false
    return true
}
