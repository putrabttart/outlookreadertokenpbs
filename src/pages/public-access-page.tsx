import { useEffect, useRef, useState } from "react"
import DOMPurify from "dompurify"
import { Check, Clock3, Copy, KeyRound, LogOut, MailCheck, RefreshCcw, ShieldCheck } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { decryptAccount, encryptAccount, type EncryptedAccountRecord } from "@/lib/crypto"
import type { ParsedCredential } from "@/lib/validation"
import { exchangeRefreshToken, fetchInbox, fetchMessageDetail, getFriendlyEmailError, type InboxMessage, type MessageDetail } from "@/lib/graph"
import {
    claimPublicAccessMessage,
    isSupabaseConfigured,
    logPublicInboxMessage,
    redeemPublicAccessToken,
    resumePublicAccessSession,
    updatePublicAccountCredential,
    type PublicAccessSession,
} from "@/lib/supabase"

const SESSION_SECRET_KEY = "outlookreader-public-session"
const POLL_INTERVAL_MS = 8000

function createSessionSecret() {
    const bytes = crypto.getRandomValues(new Uint8Array(32))
    return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")
}

function toEncryptedRecord(session: PublicAccessSession): EncryptedAccountRecord {
    return {
        id: session.account_id,
        email: session.email,
        clientId: session.client_id,
        cipherText: session.cipher_text,
        iv: session.iv,
        salt: session.salt,
        createdAt: 0,
        updatedAt: 0,
    }
}

export function PublicAccessPage() {
    const [token, setToken] = useState("")
    const [session, setSession] = useState<PublicAccessSession | null>(null)
    const [sessionSecret, setSessionSecret] = useState<string | null>(null)
    const [message, setMessage] = useState<MessageDetail | null>(null)
    const [loading, setLoading] = useState(true)
    const [checking, setChecking] = useState(false)
    const [error, setError] = useState<string | null>(null)
    const [copied, setCopied] = useState(false)
    const polling = useRef(false)
    const credentialRef = useRef<ParsedCredential | null>(null)

    useEffect(() => {
        const restore = async () => {
            const storedSecret = sessionStorage.getItem(SESSION_SECRET_KEY)
            if (!storedSecret) {
                setLoading(false)
                return
            }

            try {
                const restored = await resumePublicAccessSession(storedSecret)
                if (restored) {
                    setSessionSecret(storedSecret)
                    setSession(restored)
                } else {
                    sessionStorage.removeItem(SESSION_SECRET_KEY)
                }
            } catch {
                sessionStorage.removeItem(SESSION_SECRET_KEY)
            } finally {
                setLoading(false)
            }
        }
        restore()
    }, [])

    const checkForMessage = async (activeSession = session, secret = sessionSecret) => {
        if (!activeSession || !secret || polling.current) return
        polling.current = true
        setChecking(true)
        setError(null)

        try {
            const credential = credentialRef.current ?? await decryptAccount(toEncryptedRecord(activeSession), activeSession.access_key)
            const auth = await exchangeRefreshToken(credential)
            if (auth.refreshToken && auth.refreshToken !== credential.refreshToken) {
                const updatedCredential = { ...credential, refreshToken: auth.refreshToken }
                const encrypted = await encryptAccount(updatedCredential, activeSession.access_key, activeSession.account_id)
                await updatePublicAccountCredential(secret, encrypted)
                credentialRef.current = updatedCredential
            } else if (!credentialRef.current) {
                credentialRef.current = credential
            }
            let discoveredMessages: InboxMessage[] = []

            let messageId = activeSession.claimed_message_id
            if (!messageId) {
                const inbox = await fetchInbox(auth.accessToken)
                discoveredMessages = inbox.messages
                const activatedAt = new Date(activeSession.activated_at).getTime()
                const candidates = inbox.messages
                    .filter((item) => new Date(item.receivedDateTime).getTime() > activatedAt)
                    .sort((left, right) => new Date(left.receivedDateTime).getTime() - new Date(right.receivedDateTime).getTime())

                // Logging must not prevent the token queue from claiming a
                // message when an older database has not applied the logging
                // migration yet.
                await Promise.all(candidates.map(async (candidate) => {
                    try {
                        await logPublicInboxMessage(secret, candidate)
                    } catch (logError) {
                        console.warn("[Inbox Log Error] Message was not logged:", logError)
                    }
                }))

                for (const candidate of candidates) {
                    const result = await claimPublicAccessMessage(secret, candidate.id, candidate.receivedDateTime)
                    if (result === "used") {
                        messageId = candidate.id
                        setSession((current) => current ? { ...current, status: "used", claimed_message_id: candidate.id } : current)
                        break
                    }
                    if (result === "invalid" || result === "revoked") {
                        throw new Error("Sesi token sudah tidak berlaku")
                    }
                }
            }

            if (messageId) {
                const detail = await fetchMessageDetail(auth.accessToken, messageId)
                setMessage(detail)

                // Upsert again after the message is actually available to the
                // user. This makes the admin log reflect delivered messages,
                // even if an earlier candidate-log attempt failed.
                const deliveredCandidate = discoveredMessages.find((item) => item.id === messageId)
                if (deliveredCandidate) {
                    try {
                        await logPublicInboxMessage(secret, deliveredCandidate)
                    } catch (logError) {
                        console.warn("[Inbox Log Error] Delivered message was not logged:", logError)
                    }
                }
            }
        } catch (caught) {
            setError(getFriendlyEmailError(caught))
        } finally {
            polling.current = false
            setChecking(false)
        }
    }

    useEffect(() => {
        if (!session || !sessionSecret || message) return
        checkForMessage(session, sessionSecret)
        const interval = window.setInterval(() => checkForMessage(session, sessionSecret), POLL_INTERVAL_MS)
        return () => window.clearInterval(interval)
        // The function closes over the session passed to this effect.
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [session, sessionSecret, message])

    const handleRedeem = async (event: React.FormEvent) => {
        event.preventDefault()
        setLoading(true)
        setError(null)
        const secret = createSessionSecret()

        try {
            const nextSession = await redeemPublicAccessToken(token, secret)
            sessionStorage.setItem(SESSION_SECRET_KEY, secret)
            setSessionSecret(secret)
            setSession(nextSession)
            credentialRef.current = null
            setToken("")
        } catch (caught) {
            const detail = caught instanceof Error ? caught.message : "Token tidak valid atau sudah digunakan"
            setError(detail.includes("already been used") || detail.includes("Invalid access token")
                ? "Token tidak valid atau sudah pernah digunakan."
                : detail)
        } finally {
            setLoading(false)
        }
    }

    const endSession = () => {
        sessionStorage.removeItem(SESSION_SECRET_KEY)
        setSession(null)
        setSessionSecret(null)
        setMessage(null)
        setError(null)
        setCopied(false)
        credentialRef.current = null
    }

    const copyOwnerEmail = async () => {
        if (!session?.email) return
        await navigator.clipboard.writeText(session.email)
        setCopied(true)
        window.setTimeout(() => setCopied(false), 1600)
    }

    const cleanHtml = message ? DOMPurify.sanitize(message.bodyHtmlRaw, { USE_PROFILES: { html: true }, ADD_ATTR: ["target"] }) : ""

    if (!isSupabaseConfigured) {
        return <div className="user-shell user-brand-bg flex min-h-screen items-center justify-center p-6 text-center text-[#720002]">Layanan akses belum dikonfigurasi.</div>
    }

    return (
        <main className="user-shell user-brand-bg min-h-screen px-4 py-8 text-[#2a0709] sm:px-6">
            <div className="mx-auto flex min-h-[calc(100vh-4rem)] w-full max-w-4xl items-center justify-center">
                {!session ? (
                    <form onSubmit={handleRedeem} className="user-glass-card relative w-full max-w-md overflow-hidden rounded-[2rem] p-7 sm:p-9">
                        <div className="user-berry-gradient absolute inset-x-0 top-0 h-2" />
                        <div className="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-2xl bg-[#F4D6DC] text-[#720002]">
                            <KeyRound className="h-7 w-7" />
                        </div>
                        <p className="text-center text-xs font-black uppercase tracking-[0.22em] text-[#720002]/60">Akses privat</p>
                        <h1 className="mt-2 text-center text-3xl font-black tracking-tight text-[#720002]">Masukkan token</h1>
                        <p className="mx-auto mt-3 max-w-sm text-center text-sm leading-relaxed text-[#720002]/65">
                            Gunakan token dari admin untuk menunggu satu email baru. Token hanya berlaku satu kali dalam sesi ini.
                        </p>
                        <Input
                            autoFocus
                            autoComplete="off"
                            value={token}
                            onChange={(event) => setToken(event.target.value.toUpperCase())}
                            placeholder="TOKEN AKSES"
                            className="mt-6 h-13 rounded-2xl text-center font-mono text-base font-bold uppercase tracking-widest"
                        />
                        {error && <p className="mt-4 rounded-xl bg-[#F4D6DC] p-3 text-center text-xs font-bold text-[#720002]">{error}</p>}
                        <Button type="submit" disabled={loading || token.trim().length < 16} className="user-berry-gradient mt-5 h-12 w-full rounded-2xl text-white">
                            {loading ? "Memeriksa token..." : "Gunakan Token"}
                        </Button>
                        <div className="mt-6 flex items-center justify-center gap-2 text-xs font-semibold text-[#720002]/55">
                            <ShieldCheck className="h-4 w-4" /> Tidak ada email lama yang ditampilkan
                        </div>
                    </form>
                ) : message ? (
                    <article className="user-glass-card w-full overflow-hidden rounded-[2rem]">
                        <header className="border-b-2 border-[#720002] bg-[#F4D6DC] p-6 sm:p-8">
                            <div className="mb-4 inline-flex items-center gap-2 rounded-full bg-[#720002] px-3 py-1 text-xs font-black uppercase tracking-wider text-white">
                                <MailCheck className="h-3.5 w-3.5" /> Pesan diterima
                            </div>
                            <h1 className="text-2xl font-black text-[#720002] sm:text-3xl">{message.subject}</h1>
                            <p className="mt-3 text-sm font-bold text-[#720002]/70">Dari: {message.from}</p>
                            <div className="mt-4 flex flex-wrap items-center gap-2">
                                <span className="text-xs font-black uppercase tracking-wider text-[#720002]/55">Pemilik token</span>
                                <button type="button" onClick={copyOwnerEmail} className="inline-flex max-w-full items-center gap-2 rounded-xl border-2 border-[#720002] bg-white px-3 py-2 text-left text-xs font-bold text-[#720002]" title="Salin email">
                                    <span className="max-w-[15rem] truncate sm:max-w-none">{session.email}</span>
                                    {copied ? <Check className="h-4 w-4 shrink-0" /> : <Copy className="h-4 w-4 shrink-0" />}
                                </button>
                            </div>
                        </header>
                        <div className="bg-white p-5 sm:p-8">
                            <div className="prose max-w-none break-words text-gray-900" dangerouslySetInnerHTML={{ __html: cleanHtml }} />
                        </div>
                        <footer className="border-t-2 border-[#720002] bg-[#fff8f9] p-4 text-center text-xs font-bold text-[#720002]/60">
                            Token telah digunakan. Sesi ini hanya dapat membuka pesan ini.
                            <button type="button" onClick={endSession} className="ml-2 inline-flex items-center gap-1 font-black underline underline-offset-2">
                                <LogOut className="h-3 w-3" /> Gunakan token lain
                            </button>
                        </footer>
                    </article>
                ) : (
                    <section className="user-glass-card w-full max-w-lg rounded-[2rem] p-8 text-center sm:p-10">
                        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-[#F4D6DC] text-[#720002]">
                            <Clock3 className="h-7 w-7" />
                        </div>
                        <p className="mt-6 text-xs font-black uppercase tracking-[0.22em] text-[#720002]/55">Token aktif</p>
                        <h1 className="mt-2 text-3xl font-black text-[#720002]">Menunggu email baru</h1>
                        <p className="mt-3 text-sm leading-relaxed text-[#720002]/65">
                            Biarkan halaman ini terbuka. Hanya satu pesan yang masuk setelah token diaktifkan yang akan ditampilkan.
                        </p>
                        <div className="mt-5 flex items-center justify-center gap-2">
                            <span className="text-xs font-black uppercase tracking-wider text-[#720002]/55">Pemilik token</span>
                            <button type="button" onClick={copyOwnerEmail} className="inline-flex max-w-[15rem] items-center gap-2 rounded-xl border-2 border-[#720002] bg-white px-3 py-2 text-xs font-bold text-[#720002]" title="Salin email">
                                <span className="truncate">{session.email}</span>
                                {copied ? <Check className="h-4 w-4 shrink-0" /> : <Copy className="h-4 w-4 shrink-0" />}
                            </button>
                        </div>
                        <div className="mt-6 flex items-center justify-center gap-2 text-sm font-bold text-[#720002]">
                            <RefreshCcw className={`h-4 w-4 ${checking ? "animate-spin" : ""}`} />
                            {checking ? "Memeriksa pesan..." : "Antrean FIFO aktif"}
                        </div>
                        {error && <p className="mt-5 rounded-xl bg-[#F4D6DC] p-3 text-xs font-bold text-[#720002]">{error}</p>}
                        <button type="button" onClick={endSession} className="mt-6 inline-flex items-center gap-2 text-xs font-black text-[#720002] underline underline-offset-2">
                            <LogOut className="h-3.5 w-3.5" /> Akhiri sesi dan gunakan token lain
                        </button>
                    </section>
                )}
            </div>
        </main>
    )
}
