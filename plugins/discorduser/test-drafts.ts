import { addDraft, listDrafts, getDraft, removeDraft } from "./src/drafts.ts";

const draftId = await addDraft({
  accountId: "test",
  chatId: "123",
  senderName: "Alice",
  senderId: "456",
  inboundText: "hi",
  draftText: "hello",
});
console.log("Added:", draftId);

const list = await listDrafts();
console.log("List:", list.length, "drafts");

const draft = await getDraft(draftId);
console.log("Get:", draft?.senderName);

await removeDraft(draftId);

const listAfter = await listDrafts();
console.log("After remove:", listAfter.length, "drafts");
