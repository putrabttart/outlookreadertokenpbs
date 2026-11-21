import { HashRouter, Routes, Route, Navigate } from "react-router-dom"
import { ThemeProvider } from "./components/theme-provider"
import { Toaster } from "@/components/ui/sonner"
import { AdminPage } from "./pages/admin-page"
import { PublicAccessPage } from "./pages/public-access-page"

function RootRedirect() {
  return <Navigate to="/inbox" replace />
}

function App() {
  return (
    <ThemeProvider defaultTheme="system" storageKey="outlookreader-theme">
      <HashRouter>
        <Routes>
          <Route path="/admin/*" element={<AdminPage />} />
          <Route path="/" element={<RootRedirect />} />
          <Route path="/inbox" element={<PublicAccessPage />} />
        </Routes>
      </HashRouter>
      <Toaster />
    </ThemeProvider>
  )
}

export default App
