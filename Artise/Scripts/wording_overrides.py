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
    # Several workspaces: Element's "account" is a workspace
    "common_add_another_account": ("Add a workspace", "Añadir un espacio de trabajo", "Adicionar um espaço de trabalho"),
    # Signing in a new phone from this one with a QR code
    "common_link_new_device": ("Connect a phone", "Conectar un teléfono", "Conectar um celular"),
    "screen_onboarding_sign_in_with_qr_code": ("Scan with my other phone", "Escanear con mi otro teléfono", "Escanear com meu outro celular"),
    # Plain errors and empty screens
    "error_unknown": ("Something went wrong. Try again.", "Algo salió mal. Inténtalo de nuevo.", "Algo deu errado. Tente de novo."),
    "error_failed_loading_messages": (
        "Couldn’t load the messages. Check your connection.",
        "No se pudieron cargar los mensajes. Revisa tu conexión.",
        "Não foi possível carregar as mensagens. Confira sua conexão.",
    ),
    "error_failed_uploading_voice_message": (
        "Couldn’t send your voice message. Try again.",
        "No se pudo enviar tu mensaje de voz. Inténtalo de nuevo.",
        "Não foi possível enviar sua mensagem de voz. Tente de novo.",
    ),
    "error_failed_creating_the_permalink": ("Couldn’t create the link", "No se pudo crear el enlace", "Não foi possível criar o link"),
    "error_some_messages_have_not_been_sent": (
        "Some messages weren’t sent. Tap them to try again.",
        "Algunos mensajes no se enviaron. Tócalos para intentarlo de nuevo.",
        "Algumas mensagens não foram enviadas. Toque nelas para tentar de novo.",
    ),
    "common_offline": ("No connection", "Sin conexión", "Sem conexão"),
    "screen_roomlist_empty_title": ("No chats yet", "Todavía no hay chats", "Ainda não há conversas"),
    "screen_roomlist_empty_message": (
        "Start one with the + button, or ask Ari for anything.",
        "Empieza uno con el botón +, o pídele algo a Ari.",
        "Comece uma com o botão +, ou peça algo ao Ari.",
    ),
    "screen_roomlist_filter_favourites_empty_state_title": (
        "No favourite chats yet",
        "Todavía no tienes chats favoritos",
        "Você ainda não tem conversas favoritas",
    ),
    "screen_roomlist_filter_favourites_empty_state_subtitle": (
        "Mark a chat as a favourite from its details to keep it here.",
        "Marca un chat como favorito desde su información para tenerlo aquí.",
        "Marque uma conversa como favorita nas informações dela para mantê-la aqui.",
    ),
    "screen_roomlist_filter_unreads_empty_state_title": (
        "You’re all caught up",
        "Estás al día",
        "Você está em dia",
    ),
    "screen_roomlist_filter_invites_empty_state_title": (
        "No invites waiting",
        "No tienes invitaciones pendientes",
        "Você não tem convites pendentes",
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
    # The lines inside a chat about what changed (Element's event formatter)
    "state_event_room_avatar_changed": ("%1$s changed the chat picture", "%1$s cambió la foto del chat", "%1$s mudou a foto da conversa"),
    "state_event_room_avatar_changed_by_you": ("You changed the chat picture", "Cambiaste la foto del chat", "Você mudou a foto da conversa"),
    "state_event_room_avatar_removed": ("%1$s removed the chat picture", "%1$s quitó la foto del chat", "%1$s removeu a foto da conversa"),
    "state_event_room_avatar_removed_by_you": ("You removed the chat picture", "Quitaste la foto del chat", "Você removeu a foto da conversa"),
    "state_event_room_created": ("%1$s created the chat", "%1$s creó el chat", "%1$s criou a conversa"),
    "state_event_room_created_by_you": ("You created the chat", "Creaste el chat", "Você criou a conversa"),
    "state_event_room_join": ("%1$s joined the chat", "%1$s se unió al chat", "%1$s entrou na conversa"),
    "state_event_room_join_by_you": ("You joined the chat", "Te uniste al chat", "Você entrou na conversa"),
    "state_event_room_leave": ("%1$s left the chat", "%1$s salió del chat", "%1$s saiu da conversa"),
    "state_event_room_leave_by_you": ("You left the chat", "Saliste del chat", "Você saiu da conversa"),
    "state_event_room_name_changed": (
        "%1$s changed the chat’s name to: %2$s",
        "%1$s cambió el nombre del chat a: %2$s",
        "%1$s mudou o nome da conversa para: %2$s",
    ),
    "state_event_room_name_changed_by_you": (
        "You changed the chat’s name to: %1$s",
        "Cambiaste el nombre del chat a: %1$s",
        "Você mudou o nome da conversa para: %1$s",
    ),
    "state_event_room_name_removed": ("%1$s removed the chat’s name", "%1$s quitó el nombre del chat", "%1$s removeu o nome da conversa"),
    "state_event_room_name_removed_by_you": ("You removed the chat’s name", "Quitaste el nombre del chat", "Você removeu o nome da conversa"),
    "state_event_room_third_party_invite": (
        "%1$s invited %2$s to the chat",
        "%1$s invitó a %2$s al chat",
        "%1$s convidou %2$s para a conversa",
    ),
    "state_event_room_third_party_invite_by_you": ("You invited %1$s to the chat", "Invitaste a %1$s al chat", "Você convidou %1$s para a conversa"),
    "state_event_room_third_party_revoked_invite": (
        "%1$s cancelled %2$s’s invite to the chat",
        "%1$s canceló la invitación de %2$s al chat",
        "%1$s cancelou o convite de %2$s para a conversa",
    ),
    "state_event_room_third_party_revoked_invite_by_you": (
        "You cancelled %1$s’s invite to the chat",
        "Cancelaste la invitación de %1$s al chat",
        "Você cancelou o convite de %1$s para a conversa",
    ),
    "state_event_room_topic_removed": ("%1$s removed the chat’s description", "%1$s quitó la descripción del chat", "%1$s removeu a descrição da conversa"),
    "state_event_room_topic_removed_by_you": ("You removed the chat’s description", "Quitaste la descripción del chat", "Você removeu a descrição da conversa"),
    # Confirming it's you on a new phone, and the recovery key (plain words instead of "digital identity" and "device")
    "screen_identity_confirmation_title": ("Confirm it’s you", "Confirma que eres tú", "Confirme que é você"),
    "screen_identity_confirmation_subtitle": (
        "To read your earlier messages on this phone, confirm with your other phone or your recovery key.",
        "Para leer tus mensajes anteriores en este teléfono, confírmalo con tu otro teléfono o tu clave de recuperación.",
        "Para ler suas mensagens anteriores neste celular, confirme com seu outro celular ou sua chave de recuperação.",
    ),
    "screen_identity_confirmation_use_another_device": ("Use my other phone", "Usar mi otro teléfono", "Usar meu outro celular"),
    "screen_identity_use_another_device": ("Use my other phone", "Usar mi otro teléfono", "Usar meu outro celular"),
    "screen_identity_confirmation_use_recovery_key": ("Use my recovery key", "Usar mi clave de recuperación", "Usar minha chave de recuperação"),
    "screen_identity_confirmation_cannot_confirm": ("Don’t have either?", "¿No tienes ninguno?", "Não tem nenhum dos dois?"),
    "screen_identity_confirmed_title": ("This phone is confirmed", "Este teléfono está confirmado", "Este celular está confirmado"),
    "screen_identity_confirmed_subtitle": (
        "Your messages can be read on this phone, and the people you chat with can trust it.",
        "Tus mensajes se pueden leer en este teléfono y las personas con las que chateas pueden confiar en él.",
        "Suas mensagens podem ser lidas neste celular e as pessoas com quem você conversa podem confiar nele.",
    ),
    "screen_identity_waiting_on_other_device": ("Waiting for your other phone…", "Esperando a tu otro teléfono…", "Aguardando seu outro celular…"),
    "screen_session_verification_use_another_device_title": ("Open Artise on your other phone", "Abre Artise en tu otro teléfono", "Abra o Artise no seu outro celular"),
    "screen_session_verification_use_another_device_subtitle": (
        "Keep it open there before you start here.",
        "Déjalo abierto allí antes de empezar aquí.",
        "Deixe-o aberto lá antes de começar aqui.",
    ),
    "screen_session_verification_waiting_another_device_title": ("Start on your other phone", "Empieza en tu otro teléfono", "Comece no seu outro celular"),
    "screen_session_verification_waiting_other_device_title": ("Start on your other phone", "Empieza en tu otro teléfono", "Comece no seu outro celular"),
    "screen_session_verification_waiting_another_device_subtitle": (
        "A message should appear on your other phone. Start from there.",
        "Debería aparecer un aviso en tu otro teléfono. Empieza desde ahí.",
        "Deve aparecer um aviso no seu outro celular. Comece por lá.",
    ),
    "screen_session_verification_compare_emojis_subtitle": (
        "Check that these emojis are the same as on your other phone.",
        "Comprueba que estos emojis son los mismos que en tu otro teléfono.",
        "Confira se estes emojis são os mesmos do seu outro celular.",
    ),
    "screen_session_verification_compare_numbers_subtitle": (
        "Check that these numbers are the same as on your other phone.",
        "Comprueba que estos números son los mismos que en tu otro teléfono.",
        "Confira se estes números são os mesmos do seu outro celular.",
    ),
    "screen_session_verification_device_verified": ("Phone confirmed", "Teléfono confirmado", "Celular confirmado"),
    "screen_session_verification_request_success_title": ("Phone confirmed", "Teléfono confirmado", "Celular confirmado"),
    "screen_session_verification_complete_subtitle": (
        "Your other phone can now read and send messages.",
        "Tu otro teléfono ya puede leer y enviar mensajes.",
        "Seu outro celular já pode ler e enviar mensagens.",
    ),
    "screen_session_verification_request_success_subtitle": (
        "Your other phone can now read and send messages.",
        "Tu otro teléfono ya puede leer y enviar mensajes.",
        "Seu outro celular já pode ler e enviar mensagens.",
    ),
    "screen_session_verification_request_title": (
        "Another phone wants to confirm it’s you",
        "Otro teléfono quiere confirmar que eres tú",
        "Outro celular quer confirmar que é você",
    ),
    "screen_session_verification_request_subtitle": (
        "Confirm it so it can read your messages.",
        "Confírmalo para que pueda leer tus mensajes.",
        "Confirme para que ele possa ler suas mensagens.",
    ),
    "screen_session_verification_request_footer": (
        "Only continue if you started this on your other phone.",
        "Continúa solo si lo empezaste tú en tu otro teléfono.",
        "Continue só se você começou isso no seu outro celular.",
    ),
    "screen_session_verification_open_existing_session_title": (
        "Open Artise on a phone you already use",
        "Abre Artise en un teléfono que ya usas",
        "Abra o Artise num celular que você já usa",
    ),
    "screen_session_verification_open_existing_session_subtitle": (
        "To show it’s you and read your earlier messages.",
        "Para confirmar que eres tú y leer tus mensajes anteriores.",
        "Para confirmar que é você e ler suas mensagens anteriores.",
    ),
    "screen_session_verification_unavailable_title": (
        "You can’t confirm with this phone right now",
        "Ahora no puedes confirmar con este teléfono",
        "Agora você não pode confirmar com este celular",
    ),
    "screen_session_verification_unavailable_subtitle": (
        "Use your other phone or your recovery key.",
        "Usa tu otro teléfono o tu clave de recuperación.",
        "Use seu outro celular ou sua chave de recuperação.",
    ),
    "confirm_recovery_key_banner_title": (
        "Your earlier messages are locked",
        "Tus mensajes anteriores están bloqueados",
        "Suas mensagens anteriores estão bloqueadas",
    ),
    "confirm_recovery_key_banner_message": (
        "Enter your recovery key to read them on this phone.",
        "Escribe tu clave de recuperación para leerlos en este teléfono.",
        "Digite sua chave de recuperação para lê-las neste celular.",
    ),
    "banner_set_up_recovery_title": (
        "Keep your messages if you lose this phone",
        "Conserva tus mensajes si pierdes este teléfono",
        "Guarde suas mensagens se perder este celular",
    ),
    "banner_set_up_recovery_content": (
        "Get a recovery key, so you can read your messages on a new phone.",
        "Obtén una clave de recuperación para leer tus mensajes en un teléfono nuevo.",
        "Obtenha uma chave de recuperação para ler suas mensagens num celular novo.",
    ),
    "screen_recovery_key_confirm_error_content": ("Check the key and try again.", "Revisa la clave e inténtalo de nuevo.", "Confira a chave e tente de novo."),
    "screen_encryption_reset_title": (
        "No other phone and no recovery key? Start fresh.",
        "¿Sin otro teléfono ni clave de recuperación? Empieza de nuevo.",
        "Sem outro celular nem chave de recuperação? Comece de novo.",
    ),
    "screen_encryption_reset_bullet_2": (
        "Messages from before won’t be readable",
        "Los mensajes de antes no se podrán leer",
        "As mensagens de antes não poderão ser lidas",
    ),
    "screen_encryption_reset_bullet_3": (
        "Your other phones and contacts will need to confirm you again",
        "Tus otros teléfonos y contactos tendrán que confirmarte de nuevo",
        "Seus outros celulares e contatos precisarão confirmar você de novo",
    ),
    "screen_encryption_reset_footer": (
        "Only start fresh if you have no other phone signed in and no recovery key.",
        "Empieza de nuevo solo si no tienes otro teléfono con tu sesión abierta ni tu clave de recuperación.",
        "Só comece de novo se não tiver outro celular com sua sessão aberta nem sua chave de recuperação.",
    ),
    "screen_reset_encryption_confirmation_alert_title": ("Start fresh?", "¿Empezar de nuevo?", "Começar de novo?"),
    "screen_reset_encryption_confirmation_alert_subtitle": ("This can’t be undone.", "No se puede deshacer.", "Não dá para desfazer."),
    "screen_reset_encryption_confirmation_alert_action": ("Yes, start fresh", "Sí, empezar de nuevo", "Sim, começar de novo"),
    "screen_reset_identity_confirmation_title": (
        "Can’t confirm? Start fresh from your account.",
        "¿No puedes confirmar? Empieza de nuevo desde tu cuenta.",
        "Não consegue confirmar? Comece de novo pela sua conta.",
    ),
    "screen_reset_identity_confirmation_subtitle": (
        "You’ll go to your %1$s account to start fresh, then come back to the app.",
        "Irás a tu cuenta de %1$s para empezar de nuevo y luego volverás a la app.",
        "Você vai para sua conta %1$s para começar de novo e depois volta ao app.",
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
