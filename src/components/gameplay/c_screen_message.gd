class_name C_ScreenMessage
extends Component
## Запрос к презентации: показать игроку короткую строку поверх HUD.
## Логика вешает компонент, hud_message.gd его рисует, S_ScreenMessage снимает
## по истечении времени — тот же приём развязки, что C_Highlighted → O_OutlineVisual.
##
## Вешается на сущность игрока. Показ повторного сообщения делается
## remove+add (см. A_TravelThroughDoor._notify): прямая запись в поля компонента
## сигналов миру не шлёт, и HUD не узнал бы о новом тексте.

@export var text: String = ""
## Сколько секунд ещё показывать. Тикает S_ScreenMessage.
@export var remaining: float = 2.5
