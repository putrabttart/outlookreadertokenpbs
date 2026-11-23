import { useEffect, useState } from "react"
import { Navigate, Route, Routes } from "react-router-dom"
import {
    AccountListPanel,
    AddAccountPanel,
    AdminLoginCard,
    AdminMissingConfig,
    AdminShell,
    InboxLogTable,
    LatestLogsPreview,
    StatCards,
} from "@/components/admin/admin-dashboard"
import { EmailFilterSettingsPanel } from "@/components/admin/email-filter-settings"
import {
    addAdminManagedAccount,
    adminSignIn,
    adminSignOut,
    createAdminAccessToken,
    deleteAdminAccount,
    getAdminSession,
    isCurrentUserAdmin,
    isSupabaseConfigured,
    loadAdminAccounts,
    loadAdminAccessTokens,
    loadAdminInboxLogs,
    loadAdminEmailFilters,
    revokeAdminAccessToken,
    type AccountAccessTokenRow,
    type InboxLogRow,
    type SupabaseAccountRow,
    type AccountEmailFilterRow,
} from "@/lib/supabase"
import { toast } from "sonner"

export function AdminPage() {
    const [email, setEmail] = useState("")
    const [password, setPassword] = useState("")
    const [loading, setLoading] = useState(true)
    const [isAdmin, setIsAdmin] = useState(false)
    const [accounts, setAccounts] = useState<SupabaseAccountRow[]>([])
    const [logs, setLogs] = useState<InboxLogRow[]>([])
    const [selectedAccountId, setSelectedAccountId] = useState("")
    const [newAccountCredential, setNewAccountCredential] = useState("")
    const [accessTokens, setAccessTokens] = useState<AccountAccessTokenRow[]>([])
    const [generatedToken, setGeneratedToken] = useState<string | null>(null)
    const [emailFilters, setEmailFilters] = useState<AccountEmailFilterRow[]>([])

    const loadAdminData = async () => {
        setLoading(true)
        try {
            const [accountRows, logRows, tokenRows, filterRows] = await Promise.all([
                loadAdminAccounts(),
                // Logs are global admin history; accountId only controls the
                // selected account/token management view.
                loadAdminInboxLogs(),
                loadAdminAccessTokens(),
                loadAdminEmailFilters(),
            ])
            setAccounts(accountRows)
            setLogs(logRows)
            setAccessTokens(tokenRows)
            setEmailFilters(filterRows)
        } catch (error: unknown) {
            toast.error(error instanceof Error ? error.message : "Gagal memuat data admin")
        } finally {
            setLoading(false)
        }
    }

    useEffect(() => {
        const init = async () => {
            if (!isSupabaseConfigured) {
                setLoading(false)
                return
            }

            try {
                const session = await getAdminSession()
                if (!session) {
                    setLoading(false)
                    return
                }

                const allowed = await isCurrentUserAdmin()
                setIsAdmin(allowed)
                if (allowed) await loadAdminData()
            } catch (error: unknown) {
                toast.error(error instanceof Error ? error.message : "Gagal membuka admin")
            } finally {
                setLoading(false)
            }
        }

        init()
    }, [])

    useEffect(() => {
        if (!isAdmin) return
        const interval = window.setInterval(() => {
            void loadAdminData()
        }, 10000)
        return () => window.clearInterval(interval)
    }, [isAdmin])

    const handleLogin = async (event: React.FormEvent) => {
        event.preventDefault()
        setLoading(true)
        try {
            await adminSignIn(email, password)
            const allowed = await isCurrentUserAdmin()
            if (!allowed) {
                await adminSignOut()
                setIsAdmin(false)
                toast.error("Email ini belum diberi akses admin")
                return
            }

            setIsAdmin(true)
            toast.success("Login admin berhasil")
            await loadAdminData()
        } catch (error: unknown) {
            toast.error(error instanceof Error ? error.message : "Login admin gagal")
        } finally {
            setLoading(false)
        }
    }

    const handleSignOut = async () => {
        await adminSignOut()
        setIsAdmin(false)
        setAccounts([])
        setLogs([])
        setPassword("")
    }

    const handleDeleteAccount = async (accountId: string) => {
        if (!confirm("Hapus akun ini dari database? Log email akun ini juga akan terhapus.")) return

        setLoading(true)
        try {
            await deleteAdminAccount(accountId)
            toast.success("Akun berhasil dihapus")
            await loadAdminData()
            if (selectedAccountId === accountId) setSelectedAccountId("")
        } catch (error: unknown) {
            toast.error(error instanceof Error ? error.message : "Gagal menghapus akun")
        } finally {
            setLoading(false)
        }
    }

    const handleFilterChange = async (accountId: string) => {
        setSelectedAccountId(accountId)
        setGeneratedToken(null)
        await loadAdminData()
    }

    const handleClearFilter = async () => {
        setSelectedAccountId("")
        setGeneratedToken(null)
        await loadAdminData()
    }

    const handleGenerateToken = async (accountId: string) => {
        setLoading(true)
        try {
            const result = await createAdminAccessToken(accountId)
            setGeneratedToken(result.token)
            setSelectedAccountId(accountId)
            setAccessTokens(await loadAdminAccessTokens())
            toast.success("Token baru berhasil dibuat. Salin sekarang karena token lengkap hanya ditampilkan sekali.")
        } catch (error: unknown) {
            toast.error(error instanceof Error ? error.message : "Gagal membuat token")
        } finally {
            setLoading(false)
        }
    }

    const handleRevokeToken = async (tokenId: string) => {
        setLoading(true)
        try {
            await revokeAdminAccessToken(tokenId)
            setAccessTokens(await loadAdminAccessTokens())
            toast.success("Token berhasil dicabut")
        } catch (error: unknown) {
            toast.error(error instanceof Error ? error.message : "Gagal mencabut token")
        } finally {
            setLoading(false)
        }
    }

    const handleAddAdminAccount = async (event: React.FormEvent) => {
        event.preventDefault()
        setLoading(true)
        try {
            const importedCount = await addAdminManagedAccount(newAccountCredential)
            setNewAccountCredential("")
            toast.success(`Akun berhasil ditambahkan. ${importedCount} email terbaru dicatat.`)
            await loadAdminData()
        } catch (error: unknown) {
            toast.error(error instanceof Error ? error.message : "Gagal menambahkan akun")
        } finally {
            setLoading(false)
        }
    }

    if (!isSupabaseConfigured) return <AdminMissingConfig />

    if (!isAdmin) {
        return (
            <AdminLoginCard
                email={email}
                password={password}
                loading={loading}
                onEmailChange={setEmail}
                onPasswordChange={setPassword}
                onSubmit={handleLogin}
            />
        )
    }

    return (
        <AdminShell
            loading={loading}
            onRefresh={() => loadAdminData()}
            onSignOut={handleSignOut}
        >
            <Routes>
                <Route
                    index
                    element={
                        <>
                            <StatCards
                                accounts={accounts}
                                logs={logs}
                                selectedAccountId={selectedAccountId}
                                onFilterChange={handleFilterChange}
                            />
                            <LatestLogsPreview logs={logs} />
                        </>
                    }
                />
                <Route
                    path="add-account"
                    element={
                        <AddAccountPanel
                            loading={loading}
                            newAccountCredential={newAccountCredential}
                            onAddAccount={handleAddAdminAccount}
                            onCredentialChange={setNewAccountCredential}
                        />
                    }
                />
                <Route
                    path="accounts"
                    element={
                        <AccountListPanel
                            accounts={accounts}
                            accessTokens={accessTokens}
                            generatedToken={generatedToken}
                            loading={loading}
                            selectedAccountId={selectedAccountId}
                            onFilterChange={handleFilterChange}
                            onClearFilter={handleClearFilter}
                            onDeleteAccount={handleDeleteAccount}
                            onGenerateToken={handleGenerateToken}
                            onRevokeToken={handleRevokeToken}
                        />
                    }
                />
                <Route
                    path="logs"
                    element={
                        <InboxLogTable
                            logs={logs}
                            accounts={accounts}
                            selectedAccountId={selectedAccountId}
                            onFilterChange={handleFilterChange}
                        />
                    }
                />
                <Route path="settings" element={<EmailFilterSettingsPanel accounts={accounts} filterRows={emailFilters} />} />
                <Route path="*" element={<Navigate to="/admin" replace />} />
            </Routes>
        </AdminShell>
    )
}
