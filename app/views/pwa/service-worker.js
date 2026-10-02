// CRW-04: shows the notice of a new call that the server sent to this phone,
// and opens its page when the notice is tapped. It holds no data (BR-13).
self.addEventListener("push", (event) => {
  const { title, options } = event.data.json()
  event.waitUntil(self.registration.showNotification(title, options))
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const path = event.notification.data.path
  event.waitUntil(
    clients.matchAll({ type: "window" }).then((windows) => {
      const open = windows.find((client) => new URL(client.url).pathname === path && "focus" in client)
      return open ? open.focus() : clients.openWindow(path)
    })
  )
})
