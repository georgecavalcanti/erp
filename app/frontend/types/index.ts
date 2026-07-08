export type FlashData = {
  notice?: string
  alert?: string
}

export type AuthUser = {
  id: number
  email: string
}

export type SharedProps = {
  auth: { user: AuthUser | null }
  flash: FlashData
}
