import { useState } from "react"
import { Check, RotateCcw, Search } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { defaultEmailFilterSettings, type EmailFilterSettings } from "@/lib/email-filter"
import { saveAdminEmailFilters, type AccountEmailFilterRow, type SupabaseAccountRow } from "@/lib/supabase"
import { toast } from "sonner"

export function EmailFilterSettingsPanel({ accounts, filterRows }: { accounts: SupabaseAccountRow[]; filterRows: AccountEmailFilterRow[] }) {
    const [selectedEmails, setSelectedEmails] = useState<string[]>([])
    const [settings, setSettings] = useState<EmailFilterSettings>(defaultEmailFilterSettings)
    const [saved, setSaved] = useState(false)
    const [saving, setSaving] = useState(false)
    const [storedFilters, setStoredFilters] = useState(filterRows)
    const [accountSearch, setAccountSearch] = useState("")

    const filteredAccounts = accounts.filter((account) => account.email.toLocaleLowerCase().includes(accountSearch.trim().toLocaleLowerCase()))
    const activeFilters = storedFilters
        .filter((filter) => filter.enabled)
        .map((filter) => ({ ...filter, email: accounts.find((account) => account.id === filter.account_id)?.email }))
        .filter((filter): filter is AccountEmailFilterRow & { email: string } => Boolean(filter.email))

    const update = (key: keyof EmailFilterSettings, value: string | boolean) => {
        setSaved(false)
        setSettings((current) => ({ ...current, [key]: value }))
    }

    const persistSettings = async (nextSettings: EmailFilterSettings) => {
        const accountIds = accounts.filter((account) => selectedEmails.includes(account.email)).map((account) => account.id)
        setSaving(true)
        setSaved(false)
        try {
            await saveAdminEmailFilters(accountIds, nextSettings)
            setStoredFilters((current) => [
                ...current.filter((filter) => !accountIds.includes(filter.account_id)),
                ...accountIds.map((account_id) => ({ account_id, ...nextSettings })),
            ])
            setSaved(true)
        } catch (error) {
            toast.error(error instanceof Error ? error.message : "Gagal menyimpan filter")
        } finally {
            setSaving(false)
        }
    }

    const handleSave = async () => {
        await persistSettings(settings)
    }

    const handleReset = async () => {
        setSettings(defaultEmailFilterSettings)
        await persistSettings(defaultEmailFilterSettings)
    }

    const toggleEmail = (email: string) => {
        setSelectedEmails((current) => {
            if (current.includes(email)) {
                const next = current.filter((item) => item !== email)
                const nextAccount = accounts.find((account) => account.email === next[0])
                const nextFilter = storedFilters.find((filter) => filter.account_id === nextAccount?.id)
                setSettings(nextFilter ?? defaultEmailFilterSettings)
                setSaved(false)
                return next
            }

            if (current.length === 0) {
                const account = accounts.find((item) => item.email === email)
                const filter = storedFilters.find((item) => item.account_id === account?.id)
                setSettings(filter ?? defaultEmailFilterSettings)
            }
            setSaved(false)
            return [...current, email]
        })
    }

    return (
        <Card className="border-3 border-foreground bg-[#FFF8F9] shadow-[6px_6px_0_#720002]">
            <CardHeader>
                <CardTitle className="text-[#720002]">Filter Email Masuk</CardTitle>
                <CardDescription>
                    Konfigurasi disimpan di database berdasarkan akun dan tidak mengubah data akun yang sudah ada.
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-5">
                <div className="space-y-3 rounded-xl border-2 border-[#720002] bg-white p-3">
                    <div>
                        <p className="text-sm font-black text-[#720002]">Terapkan filter untuk akun</p>
                        <p className="text-xs text-[#720002]/65">Pilih satu atau beberapa email. Filter setiap akun dapat berbeda.</p>
                    </div>
                    {accounts.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada akun.</p> : (
                        <>
                            <div className="relative">
                                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#720002]/60" />
                                <Input
                                    value={accountSearch}
                                    onChange={(event) => setAccountSearch(event.target.value)}
                                    placeholder="Cari email akun..."
                                    aria-label="Cari akun untuk filter"
                                    className="h-9 border-[#720002] pl-9"
                                />
                            </div>
                            <div className="max-h-56 overflow-y-auto rounded-lg border border-[#720002]/30 p-1">
                                {filteredAccounts.length === 0 ? (
                                    <p className="p-3 text-sm text-muted-foreground">Akun tidak ditemukan.</p>
                                ) : filteredAccounts.map((account) => (
                                    <label key={account.id} className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm font-bold text-[#720002] hover:bg-[#F4D6DC]">
                                        <input type="checkbox" checked={selectedEmails.includes(account.email)} onChange={() => toggleEmail(account.email)} className="h-4 w-4 accent-[#720002]" />
                                        <span className="truncate">{account.email}</span>
                                    </label>
                                ))}
                            </div>
                        </>
                    )}
                    {selectedEmails.length === 0 && <p className="text-xs font-bold text-amber-700">Pilih minimal satu akun sebelum menyimpan.</p>}
                </div>
                <label className="flex cursor-pointer items-center gap-3 rounded-xl border-2 border-[#720002] bg-white p-3 text-sm font-black text-[#720002]">
                    <input
                        type="checkbox"
                        checked={settings.enabled}
                        onChange={(event) => update("enabled", event.target.checked)}
                        className="h-5 w-5 accent-[#720002]"
                    />
                    Aktifkan filter email
                </label>

                <div className="grid gap-4 md:grid-cols-2">
                    <label className="space-y-2 text-sm font-bold text-[#720002] md:col-span-2">
                        <span>Keterangan filter</span>
                        <Input
                            value={settings.description}
                            onChange={(event) => update("description", event.target.value)}
                            placeholder="Contoh: Filter kode household Netflix"
                            disabled={selectedEmails.length === 0}
                        />
                        <span className="block text-xs font-normal text-[#720002]/65">Catatan ini ditampilkan pada tabel daftar akun terfilter.</span>
                    </label>
                    <label className="space-y-2 text-sm font-bold text-[#720002]">
                        <span>Email pengirim mengandung</span>
                        <Input
                            value={settings.sender}
                            onChange={(event) => update("sender", event.target.value)}
                            placeholder="info@account.netflix.com"
                            disabled={!settings.enabled}
                        />
                        <span className="block text-xs font-normal text-[#720002]/65">Kosongkan untuk mengabaikan pengirim, cocok untuk testing email forward.</span>
                    </label>
                    <label className="space-y-2 text-sm font-bold text-[#720002]">
                        <span>Subjek mengandung</span>
                        <Input
                            value={settings.subjectContains}
                            onChange={(event) => update("subjectContains", event.target.value)}
                            placeholder="Kode akses sementaramu"
                            disabled={!settings.enabled}
                        />
                    </label>
                    <label className="space-y-2 text-sm font-bold text-[#720002] md:col-span-2">
                        <span>Isi email mengandung</span>
                        <Input
                            value={settings.bodyContains}
                            onChange={(event) => update("bodyContains", event.target.value)}
                            placeholder="kode akses sementara"
                            disabled={!settings.enabled}
                        />
                    </label>
                </div>

                <div className="flex flex-wrap gap-3">
                    <Button onClick={handleSave} disabled={selectedEmails.length === 0 || saving}>
                        <Check className="h-4 w-4" /> {saving ? "Menyimpan..." : "Simpan filter"}
                    </Button>
                    <Button variant="outline" onClick={handleReset} disabled={selectedEmails.length === 0 || saving} className="border-[#720002] bg-white text-[#720002] hover:bg-[#F4D6DC] hover:text-[#720002] disabled:text-[#720002]/50">
                        <RotateCcw className="h-4 w-4" /> Kembalikan default
                    </Button>
                    {saved && <p className="self-center text-sm font-bold text-emerald-700">Filter tersimpan di database.</p>}
                </div>

                <div className="space-y-3 border-t-2 border-[#720002]/30 pt-5">
                    <div>
                        <h3 className="font-black text-[#720002]">Daftar Akun Terfilter</h3>
                        <p className="text-xs text-[#720002]/65">Hanya menampilkan akun dengan filter yang sedang aktif.</p>
                    </div>
                    <div className="overflow-x-auto rounded-lg border-2 border-[#720002] bg-white">
                        <table className="w-full min-w-[900px] text-left text-sm">
                            <thead className="bg-[#720002] text-white">
                                <tr>
                                    <th className="px-3 py-2">Akun</th>
                                    <th className="px-3 py-2">Keterangan</th>
                                    <th className="px-3 py-2">Pengirim</th>
                                    <th className="px-3 py-2">Subjek</th>
                                    <th className="px-3 py-2">Isi Email</th>
                                </tr>
                            </thead>
                            <tbody className="bg-white text-[#190304]">
                                {activeFilters.length === 0 ? (
                                    <tr><td colSpan={5} className="px-3 py-6 text-center text-muted-foreground">Belum ada akun dengan filter aktif.</td></tr>
                                ) : activeFilters.map((filter) => (
                                    <tr key={filter.account_id} className="border-t border-[#720002]/20 align-top">
                                        <td className="px-3 py-2 font-bold text-[#720002]">{filter.email}</td>
                                        <td className="px-3 py-2 text-[#190304]">{filter.description || "-"}</td>
                                        <td className="px-3 py-2 text-[#190304]">{filter.sender || "Semua pengirim"}</td>
                                        <td className="px-3 py-2 text-[#190304]">{filter.subjectContains || "Semua subjek"}</td>
                                        <td className="px-3 py-2 text-[#190304]">{filter.bodyContains || "Semua isi"}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>
            </CardContent>
        </Card>
    )
}
