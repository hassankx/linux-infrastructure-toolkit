# The DevOps Story: One Shop, One Click, Zero Downtime

Meet Maya. She runs an online shop, `shop.example.com`. Every day, thousands of people click "Buy." Maya's job, as the DevOps engineer, is to make sure those clicks always work, and that new features reach customers without breaking anything.

This story walks through her day in order. Each part answers one interview question in plain language. The full answers are in [DevOps_Interview_QA.md](DevOps_Interview_QA.md).

![A customer's click travelling through six steps to the shop](media/request_flow.gif)

## Part 1: The click

A customer types `shop.example.com` and presses Enter.

1. **The phone book (DNS).** The browser asks, "Where is shop.example.com?" The answer is an address, like a street number for the shop.
2. **The secure door (TLS).** The browser and the server agree on a secret code, so nobody on the road can read the order.
3. **The front desk (load balancer).** Many servers are waiting. The load balancer sends the customer to one that is healthy.
4. **The receptionist (ingress).** The receptionist reads the request. "You want the cart? Go to the cart room."
5. **The room sign (Service).** The cart room has one fixed sign, even though several workers are inside. The sign picks one free worker.
6. **The worker (pod).** The worker answers, and the answer goes back the same way.

**Maya's rule:** when something breaks, check the path in order. Is the phone book right? Is the front desk sending people to healthy workers? Is the sign pointing at the right room?

## Part 2: The packing box (Docker)

Maya packs each app into a container, a sealed box with everything it needs.

- `docker run` opens the box, gives it its own space and a limited amount of memory, and starts the app.
- The box has two labels: **ENTRYPOINT** is the main job ("always run the app"), and **CMD** is the default option ("use port 8000 unless told otherwise").

## Part 3: Keeping the workers running (Kubernetes)

Maya uses Kubernetes as a manager for the workers.

- **Deployment:** "Always keep 3 copies of the shop running."
- **StatefulSet:** "The database workers each have a name and a locker that stays with them."
- **DaemonSet:** "One monitoring helper on every computer."
- **Job:** "Run the nightly cleanup once, then stop."

Two checks keep the workers honest:
- **Readiness:** "Are you ready for customers?" If not, the sign stops sending people to you. You are not restarted.
- **Liveness:** "Are you still alive?" If not, the manager restarts you.

When a worker keeps crashing (CrashLoopBackOff), Maya reads its last words in the logs before she changes anything.

## Part 4: Shipping new features safely (CI/CD)

Every change follows the same road:

1. A developer submits the change for review.
2. Tests and security scans run automatically.
3. The image is labelled with the change's ID and stored.
4. It goes to a test shop (staging) first.
5. A person approves it for the real shop.
6. Workers are replaced gradually, so customers never see an empty shop.

![From a commit to production, with a rollback if things go wrong](media/cicd_rollback.gif)

If errors jump, Maya presses one button: **roll back**. The shop returns to yesterday's version in minutes.

## Part 5: The safe, locked storage room (Terraform)

Maya describes all the shop's infrastructure in code. Before any change, she runs a plan that shows exactly what will change.

- **Lock:** only one person can change the infrastructure at a time.
- **Stable names:** each item has its own name, so removing one does not rename the rest.
- **Drift check:** if someone changes something by hand, the nightly check catches it.

## Part 6: Watching the shop (monitoring)

Maya watches three things:
- **Logs:** the story of each event.
- **Metrics:** the numbers over time, like how many orders per minute.
- **Traces:** the path of one customer's order, showing exactly which step was slow.

Alerts go to a person only when customers are affected, not for every small blip.

## Part 7: Keeping the shop safe

- Container images are scanned and signed before they run.
- Each person gets only the permissions their job needs.
- Passwords are kept in a vault, not in code.
- A disaster plan says how long the shop can be down and how much data can be lost, and it is tested.

---

**The moral of Maya's story:** a good DevOps system is one where every step is visible, every change can be undone, and customers never notice that anything changed.
