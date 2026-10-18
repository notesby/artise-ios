#!/usr/bin/env python3
#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Writes Artise/Resources/StringOverrides/<language>.lproj/Wording.strings: Element's texts in Artise's words.

The words follow the UX plan's word list: chat instead of room, sign out instead of "remove this device", "espacio de
trabajo" instead of server (Matrix spaces keep "espacio"). Element's string keys are shared by both apps, so this table is
the Android app's (tools/artise/wording_overrides.py there); keep the two the same. Run it after editing the table:

    python3 Artise/Scripts/wording_overrides.py

Android's %1$s placeholders become %1$@. Keys iOS doesn't have (Android-only texts) are left out. Portuguese is
Brazilian; the pt folder also covers pt-BR phones.
"""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from apply_string_overrides import load_strings  # noqa: E402

# key: (English, Spanish, Portuguese)
WORDING = {
    # Signing out
    "action_signout": ("Sign out", "Cerrar sesión", "Sair"),
    "action_signout_anyway": ("Sign out anyway", "Cerrar sesión de todos modos", "Sair mesmo assim"),
    "common_signing_out": ("Signing out", "Cerrando sesión", "Saindo"),
    "screen_signout_preference_item": ("Sign out", "Cerrar sesión", "Sair"),
    "screen_signout_confirmation_dialog_title": ("Sign out?", "¿Cerrar sesión?", "Sair?"),
    "screen_signout_confirmation_dialog_submit": ("Sign out", "Cerrar sesión", "Sair"),
    "screen_signout_confirmation_dialog_content": (
        "Your chats will no longer show on this phone. You can sign back in anytime.",
        "Tus chats dejarán de verse en este teléfono. Podrás volver a entrar cuando quieras.",
        "Suas conversas deixarão de aparecer neste celular. Você pode entrar de novo quando quiser.",
    ),
    "screen_signout_in_progress_dialog_content": ("Signing out…", "Cerrando sesión…", "Saindo…"),
    "screen_app_lock_signout_alert_title": ("Signing you out", "Cerrando tu sesión", "Encerrando sua sessão"),
    "screen_signout_save_recovery_key_title": (
        "Make sure you have your recovery key before signing out",
        "Asegúrate de tener tu clave de recuperación antes de cerrar sesión",
        "Confira se você tem sua chave de recuperação antes de sair",
    ),
    "screen_signout_save_recovery_key_subtitle": (
        "This is the only phone you’re signed in on. After signing out, you’ll need your recovery key to read your earlier messages when you sign in again.",
        "Este es el único teléfono con tu sesión abierta. Después de cerrar sesión, necesitarás tu clave de recuperación para leer tus mensajes anteriores cuando vuelvas a entrar.",
        "Este é o único celular com sua sessão aberta. Depois de sair, você vai precisar da sua chave de recuperação para ler suas mensagens anteriores quando entrar de novo.",
    ),
    "screen_signout_recovery_disabled_subtitle": (
        "This is the only phone you’re signed in on. After signing out, you’ll need your recovery key to read your earlier messages when you sign in again.",
        "Este es el único teléfono con tu sesión abierta. Después de cerrar sesión, necesitarás tu clave de recuperación para leer tus mensajes anteriores cuando vuelvas a entrar.",
        "Este é o único celular com sua sessão aberta. Depois de sair, você vai precisar da sua chave de recuperação para ler suas mensagens anteriores quando entrar de novo.",
    ),
    "screen_signout_key_backup_disabled_subtitle": (
        "This is the only phone you’re signed in on. After signing out, you’ll need your recovery key to read your earlier messages when you sign in again.",
        "Este es el único teléfono con tu sesión abierta. Después de cerrar sesión, necesitarás tu clave de recuperación para leer tus mensajes anteriores cuando vuelvas a entrar.",
        "Este é o único celular com sua sessão aberta. Depois de sair, você vai precisar da sua chave de recuperação para ler suas mensagens anteriores quando entrar de novo.",
    ),
    "screen_signout_key_backup_offline_subtitle": (
        "Your messages’ keys were still being saved when you went offline. Reconnect so they’re saved before you sign out.",
        "Las claves de tus mensajes se estaban guardando cuando perdiste la conexión. Vuelve a conectarte para que se guarden antes de cerrar sesión.",
        "As chaves das suas mensagens ainda estavam sendo salvas quando você ficou sem conexão. Conecte-se de novo para que sejam salvas antes de sair.",
    ),
    "screen_signout_key_backup_ongoing_subtitle": (
        "Please wait for this to finish before signing out.",
        "Espera a que termine antes de cerrar sesión.",
        "Espere terminar antes de sair.",
    ),
    # Chat list
    "screen_roomlist_a11y_create_message": ("Start a new chat", "Empezar un chat nuevo", "Começar uma conversa nova"),
    "screen_roomlist_filter_rooms": ("Groups", "Grupos", "Grupos"),
    "screen_roomlist_filter_rooms_empty_state_title": (
        "You’re not in any group chat yet",
        "Todavía no estás en ningún chat de grupo",
        "Você ainda não está em nenhuma conversa em grupo",
    ),
    "screen_roomlist_filter_people_empty_state_title": (
        "You don’t have any one-to-one chats yet",
        "Todavía no tienes chats con una sola persona",
        "Você ainda não tem conversas individuais",
    ),
    "screen_roomlist_filter_low_priority": ("Less important", "Menos importantes", "Menos importantes"),
    "screen_roomlist_filter_low_priority_empty_state_title": (
        "You don’t have any less important chats yet",
        "Todavía no tienes chats menos importantes",
        "Você ainda não tem conversas menos importantes",
    ),
    "screen_roomlist_tombstoned_room_description": ("This chat has been upgraded", "Este chat se actualizó", "Esta conversa foi atualizada"),
    # Creating a chat
    "screen_create_room_action_create_room": ("New group chat", "Nuevo chat de grupo", "Nova conversa em grupo"),
    "screen_create_room_new_room_title": ("New group chat", "Nuevo chat de grupo", "Nova conversa em grupo"),
    "screen_create_room_error_creating_room": ("Couldn’t create the chat", "No se pudo crear el chat", "Não foi possível criar a conversa"),
    "screen_create_room_public_option_description": (
        "Anyone can find this chat. You can change this anytime in the chat’s settings.",
        "Cualquiera puede encontrar este chat. Puedes cambiarlo cuando quieras en los ajustes del chat.",
        "Qualquer pessoa pode encontrar esta conversa. Você pode mudar isso quando quiser nas configurações da conversa.",
    ),
    "screen_create_room_room_visibility_section_title": ("Who can find it", "Quién puede encontrarlo", "Quem pode encontrar"),
    "action_create_room": ("Create group chat", "Crear chat de grupo", "Criar conversa em grupo"),
    "common_creating_room": ("Creating chat…", "Creando chat…", "Criando conversa…"),
    "common_topic_placeholder": ("What’s this chat about?", "¿De qué trata este chat?", "Sobre o que é esta conversa?"),
    # A chat's details
    "screen_room_details_title": ("Chat info", "Información del chat", "Informações da conversa"),
    "screen_room_details_badge_public": ("Public chat", "Chat público", "Conversa pública"),
    "screen_room_details_edition_error_title": ("Couldn’t update the chat", "No se pudo actualizar el chat", "Não foi possível atualizar a conversa"),
    "screen_room_details_error_muting": (
        "Couldn’t mute this chat. Try again.",
        "No se pudo silenciar este chat. Inténtalo de nuevo.",
        "Não foi possível silenciar esta conversa. Tente de novo.",
    ),
    "screen_room_details_error_unmuting": (
        "Couldn’t unmute this chat. Try again.",
        "No se pudo quitar el silencio de este chat. Inténtalo de nuevo.",
        "Não foi possível reativar o som desta conversa. Tente de novo.",
    ),
    "screen_room_details_leave_room_title": ("Leave chat", "Salir del chat", "Sair da conversa"),
    "screen_room_details_share_room_title": ("Share chat", "Compartir chat", "Compartilhar conversa"),
    "screen_room_roles_and_permissions_room_details": ("Chat details", "Detalles del chat", "Detalhes da conversa"),
    "screen_room_member_list_room_members_header_title": ("People in the chat", "Personas en el chat", "Pessoas na conversa"),
    "screen_room_member_list_manage_member_unban_message": (
        "They’ll be able to join this chat again if invited.",
        "Podrá volver a unirse a este chat si lo invitan.",
        "Poderá entrar nesta conversa de novo se for convidado.",
    ),
    "screen_bottom_sheet_manage_room_member_kick_member_confirmation_description": (
        "They’ll be able to join this chat again if invited.",
        "Podrá volver a unirse a este chat si lo invitan.",
        "Poderá entrar nesta conversa de novo se for convidado.",
    ),
    "screen_room_notification_settings_room_custom_settings_title": (
        "In this chat, notify me for",
        "En este chat, avisarme de",
        "Nesta conversa, me avisar sobre",
    ),
    "screen_notification_settings_mentions_only_disclaimer": (
        "This workspace doesn’t support this option in encrypted chats, so you may not be notified in some chats.",
        "Este espacio de trabajo no admite esta opción en chats cifrados, así que puede que no te avise de algunos chats.",
        "Este espaço de trabalho não aceita esta opção em conversas criptografadas, então você pode não ser avisado de algumas conversas.",
    ),
    "screen_room_notification_settings_mentions_only_disclaimer": (
        "This workspace doesn’t support this option in encrypted chats, so you won’t be notified in this chat.",
        "Este espacio de trabajo no admite esta opción en chats cifrados, así que no te avisará de este chat.",
        "Este espaço de trabalho não aceita esta opção em conversas criptografadas, então você não será avisado desta conversa.",
    ),
    # Joining and inviting
    "screen_room_directory_search_title": ("Public chats", "Chats públicos", "Conversas públicas"),
    "screen_start_chat_join_room_by_address_action": ("Join a chat by its address", "Unirse a un chat por su dirección", "Entrar numa conversa pelo endereço"),
    "screen_start_chat_join_room_by_address_room_found": ("Chat found", "Chat encontrado", "Conversa encontrada"),
    "screen_start_chat_join_room_by_address_room_not_found": ("Chat not found", "Chat no encontrado", "Conversa não encontrada"),
    "screen_start_chat_join_room_by_address_supporting_text": (
        "e.g. #chat-name:artise.co",
        "p. ej., #nombre-del-chat:artise.co",
        "ex.: #nome-da-conversa:artise.co",
    ),
    "screen_invite_users_confirm_dialog_title_one_user": (
        "Invite a new person to this chat?",
        "¿Invitar a una persona nueva a este chat?",
        "Convidar uma pessoa nova para esta conversa?",
    ),
    "screen_invite_users_confirm_dialog_title_mutiple_users": (
        "Invite new people to this chat?",
        "¿Invitar a personas nuevas a este chat?",
        "Convidar pessoas novas para esta conversa?",
    ),
    "screen_invite_users_confirm_dialog_subtitle_one_user": (
        "You don’t have any chats with this person yet. Confirm you want to invite them to this chat.",
        "Todavía no tienes chats con esta persona. Confirma que quieres invitarla a este chat.",
        "Você ainda não tem conversas com essa pessoa. Confirme que quer convidá-la para esta conversa.",
    ),
    "screen_invite_users_confirm_dialog_subtitle_multiple_users": (
        "You don’t have any chats with these people yet. Confirm you want to invite them to this chat.",
        "Todavía no tienes chats con estas personas. Confirma que quieres invitarlas a este chat.",
        "Você ainda não tem conversas com essas pessoas. Confirme que quer convidá-las para esta conversa.",
    ),
    "screen_join_room_title_knock": ("Want to join this chat?", "¿Quieres unirte a este chat?", "Quer entrar nesta conversa?"),
    "screen_join_room_cancel_knock_alert_description": (
        "Cancel your request to join this chat?",
        "¿Cancelar tu solicitud para unirte a este chat?",
        "Cancelar seu pedido para entrar nesta conversa?",
    ),
    "screen_join_room_knock_sent_description": (
        "You’ll get an invite to the chat if your request is accepted.",
        "Recibirás una invitación al chat si aceptan tu solicitud.",
        "Você vai receber um convite para a conversa se seu pedido for aceito.",
    ),
    "screen_join_room_decline_and_block_alert_message": (
        "Decline the invite to this chat? %1$s also won’t be able to contact you or invite you to chats.",
        "¿Rechazar la invitación a este chat? %1$s tampoco podrá escribirte ni invitarte a chats.",
        "Recusar o convite para esta conversa? %1$s também não poderá falar com você nem te convidar para conversas.",
    ),
    "screen_join_room_loading_alert_title": (
        "We couldn’t show this chat’s preview",
        "No pudimos mostrar la vista previa de este chat",
        "Não conseguimos mostrar a prévia desta conversa",
    ),
    "screen_join_room_loading_alert_message": (
        "Check your connection. The workspace may also not be answering.",
        "Revisa tu conexión. También puede que el espacio de trabajo no esté respondiendo.",
        "Confira sua conexão. O espaço de trabalho também pode não estar respondendo.",
    ),
    "screen_join_room_subtitle_no_preview": (
        "You need to be in this chat to see its messages.",
        "Tienes que estar en este chat para ver sus mensajes.",
        "Você precisa estar nesta conversa para ver as mensagens.",
    ),
    "error_invalid_invite": (
        "The chat no longer exists or the invite has expired.",
        "El chat ya no existe o la invitación ya no es válida.",
        "A conversa não existe mais ou o convite não vale mais.",
    ),
    # Common words
    "common_room": ("Chat", "Chat", "Conversa"),
    "common_room_name": ("Chat name", "Nombre del chat", "Nome da conversa"),
    "common_no_room_name": ("No chat name", "Chat sin nombre", "Conversa sem nome"),
    "common_private_room": ("Private chat", "Chat privado", "Conversa privada"),
    "common_public_room": ("Public chat", "Chat público", "Conversa pública"),
    "a11y_room_avatar": ("Chat picture", "Foto del chat", "Foto da conversa"),
    "action_leave_room": ("Leave chat", "Salir del chat", "Sair da conversa"),
    "action_report_room": ("Report chat", "Denunciar chat", "Denunciar conversa"),
    "common_leaving_room": ("Leaving chat", "Saliendo del chat", "Saindo da conversa"),
    "common_current_user_left_room": ("Left the chat", "Saliste del chat", "Você saiu da conversa"),
    "common_android_shortcuts_remove_reason_left_room": ("You left the chat", "Saliste del chat", "Você saiu da conversa"),
    "dialog_room_reported": ("Chat reported", "Chat denunciado", "Conversa denunciada"),
    "dialog_room_reported_and_left": ("Reported and left the chat", "Denunciaste y saliste del chat", "Você denunciou e saiu da conversa"),
    "screen_room_permalink_same_room_android": ("You’re already in this chat", "Ya estás en este chat", "Você já está nesta conversa"),
    "common_server_unreachable": ("Workspace not answering", "El espacio de trabajo no responde", "O espaço de trabalho não está respondendo"),
    "common_server_not_supported": ("Workspace not supported", "Espacio de trabajo no compatible", "Espaço de trabalho não compatível"),
    "error_network_or_server_issue": (
        "Check your connection. The workspace may also not be answering.",
        "Revisa tu conexión. También puede que el espacio de trabajo no esté respondiendo.",
        "Confira sua conexão. O espaço de trabalho também pode não estar respondendo.",
    ),
    "crypto_history_visible": (
        "This chat lets new members read earlier messages. %1$s",
        "Este chat permite que quienes se unan lean los mensajes anteriores. %1$s",
        "Esta conversa permite que quem entrar leia as mensagens anteriores. %1$s",
    ),
    "crypto_event_key_forwarded_known_profile_dialog_content": (
        "%1$s (%2$s) shared this message because you weren’t in the chat when it was sent.",
        "%1$s (%2$s) compartió este mensaje porque no estabas en el chat cuando se envió.",
        "%1$s (%2$s) compartilhou esta mensagem porque você não estava na conversa quando ela foi enviada.",
    ),
    "crypto_event_key_forwarded_unknown_profile_dialog_content": (
        "%1$s shared this message because you weren’t in the chat when it was sent.",
        "%1$s compartió este mensaje porque no estabas en el chat cuando se envió.",
        "%1$s compartilhou esta mensagem porque você não estava na conversa quando ela foi enviada.",
    ),
}

HEADER = """/*
 Copyright 2026 Artise.

 SPDX-License-Identifier: AGPL-3.0-only

 Element's texts in Artise's words (chat, sign out, espacio de trabajo). Generated by
 Artise/Scripts/wording_overrides.py; edit the table there, not this file.
*/
"""

LANGUAGES = ("en", "es", "pt")


def ios_text(text):
    """%1$s → %1$@, and escaped for a .strings file."""
    text = re.sub(r"%(\d+\$)?s", lambda match: f"%{match.group(1) or ''}@", text)
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def ios_keys(root):
    return set(load_strings(root / "ElementX/Resources/Localizations/en.lproj/Localizable.strings"))


def wording_for_ios(root):
    """The table's keys that exist on iOS."""
    keys = ios_keys(root)
    return {key: texts for key, texts in WORDING.items() if key in keys}


def main():
    root = pathlib.Path(__file__).resolve().parents[2]
    wording = wording_for_ios(root)
    for index, language in enumerate(LANGUAGES):
        lines = [f'"{key}" = "{ios_text(texts[index])}";' for key, texts in wording.items()]
        path = root / "Artise/Resources/StringOverrides" / f"{language}.lproj" / "Wording.strings"
        path.write_text(HEADER + "\n" + "\n".join(lines) + "\n", encoding="utf-8")
    skipped = sorted(set(WORDING) - set(wording))
    print(f"{len(wording)} texts written; not on iOS: {', '.join(skipped) or 'none'}")


if __name__ == "__main__":
    main()
