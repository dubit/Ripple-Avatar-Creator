# Slash Commands Guide

This guide explains the slash command system for admin/debug functionality in-game.

## What are Slash Commands?

Slash commands provide a quick way for high-rank users (developers, moderators, admins) to execute model methods and controller actions directly from the chat window for testing and debugging purposes.

**Key Features:**
- **Convention-based**: Any model method or controller action automatically becomes a slash command - zero configuration needed
- **Permission-based**: Only users with rank 200+ in the owning group can use commands
- **Auto-discovered**: Commands are automatically registered when the server starts
- **Type-safe**: Arguments are automatically parsed to numbers, booleans, or strings

## Architecture Overview

The slash command system consists of three components and follows the same Intent/StateChanged patterns as the rest of the MVC architecture:

- **SlashCommandService** (server): Discovers models and controllers, validates permissions, executes commands
- **SlashCommandClient** (client): Listens to TextChatService and sends `SlashCommandIntent` to server
- **ChatMessageClient** (client): Receives `SlashCommandStateChanged` events and displays in chat window

### Event Naming Consistency

The slash command system follows the universal MVC event naming conventions:

- **`SlashCommandIntent`** (Client → Server): Command execution requests from client
- **`SlashCommandStateChanged`** (Server → Client): Command feedback and results

This matches the pattern used by all other systems:
- Controllers use `[Name]Intent` events (e.g., `BasketIntent`, `StoresIntent`)
- Models sync through `[Name]State` Bolt RemoteProperties (e.g., `BasketState`, `StoresState`)

```
┌─────────────────────────────────────────────────────────────────────┐
│                     USER TYPES SLASH COMMAND                         │
│          /favouritesmodel toggle Asset:123  OR  /basketcontroller Clear      │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
                   ┌──────────────────────┐
                   │ SlashCommandClient   │  ← Client-side utility
                   │ (Client)             │    Intercepts chat commands
                   └──────────┬───────────┘
                              │
                              │ Bolt ReliableEvent:FireServer()
                              │
                              ▼
                   ┌──────────────────────┐
                   │ SlashCommandService  │  ← Server-side service
                   │ (Server)             │    Validates & executes
                   └──────────┬───────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
                ▼                           ▼
       ┌────────────────┐         ┌────────────────┐
       │ Model Method   │         │ Controller     │
       │ Execution      │         │ Bolt Event     │
       └────────┬───────┘         └────────┬───────┘
                │                          │
                │                          │ Fires existing Bolt event
                │                          │
                ▼                          ▼
       ┌────────────────┐         ┌────────────────┐
       │ State Sync     │         │ Controller     │
       │ (Bolt)         │         │ OnServerEvent  │ ← Uses existing logic
       └────────────────┘         └────────┬───────┘
                                           │
                                           ▼
                                  ┌────────────────┐
                                  │ Model Update & │
                                  │ State Sync     │
                                  └────────────────┘
```

## Using Slash Commands

### Command Format

**Model Commands:**
```
/modelname methodname arg1 arg2 ...
```

**Controller Commands:**
```
/controllername actionname arg1 arg2 ...
```

**Model Examples:**
```
/basketmodel clear
/favouritesmodel toggle Asset:123
/outfitsmodel rename 1 Party
/worldoptionsmodel reset
```

**Controller Examples:**
```
/basketcontroller Clear
/avatarcontroller Undo
/avatarcontroller TakeOffAll
/worldoptionscontroller Reset
```

### Permission Requirements

Commands are only available to users who meet these criteria:

- **Group-owned games**: User must have rank 200+ in the group that owns the game
- **User-owned games**: All users can use commands (for testing in Studio)

The group ID is **automatically detected** when the server starts - no configuration needed!

## Discovering Available Commands

### Using /commands Command

The `/commands` command provides automatic discovery of all available slash commands:

**List all commands:**
```
/commands
```

Shows all models (User/Server scoped) and controllers with their command names.

**View specific command details:**
```
/commands modelname
/commands controllername
```

Shows all available methods (for models) or actions (for controllers) with usage examples.

**Examples:**
```
/commands                      → Lists all available commands
/commands basketmodel          → Shows methods: add, clear, indexOf, take
/commands basketcontroller     → Shows actions: Add, AddMany, Clear, Remove, RemoveMany
```

The help system automatically:
- **Discovers model methods** via runtime introspection of the model metatable
- **Discovers controller actions** by reading `Network.Actions`
- **Filters out** private methods (starting with `_`) and internal implementation details
- **Displays in chat** so all players with permission can see the information

### Using /state Command

The `/state` command provides instant visibility into model state for debugging and QA:

**View all model state:**
```
/state
```

Shows the current state of all user-scoped and server-scoped models with their property values.

**View specific model state:**
```
/state modelname
```

Shows the current state of a specific model with all its properties.

**Examples:**
```
/state                     → Shows all model states (user and server)
/state basketmodel         → Shows: items: { { targetId: 123, kind: "Asset", ... } }
/state favouritesmodel     → Shows: items: { "Asset:123", "Bundle:45" }
```

The state query system automatically:
- **Introspects model properties** via runtime inspection (same pattern as `/commands`)
- **Filters out internal fields** (ownerId, remoteEvent, private fields, functions)
- **Shows only game-relevant data** for clean, readable output
- **Works with all models** - zero instrumentation required
- **Displays in chat** for easy sharing with team members

**Use cases:**
- **Designers**: Verify game state during playtesting
- **QA**: Confirm expected state changes after actions
- **Developers**: Debug state issues without adding print statements
- **Support**: Quickly check player data for support tickets

### Zero Configuration Required

Both models and controllers are **fully discoverable without any additional code**:

- **Models**: Methods are discovered from the model's metatable at runtime
- **Controllers**: Actions are discovered from `Network.Actions` automatically

No per-model or per-controller configuration needed!

## Available Commands

Commands are automatically generated for all models and controllers. The available commands depend on what you've created:

### User-Scoped Models

User-scoped models (in `ServerScriptService/models/user/`) operate on the player's own data.

**Example - BasketModel / FavouritesModel / StoresModel:**
- `/basketmodel clear` - Empty your basket
- `/favouritesmodel toggle Asset:123` - Favourite (or unfavourite) asset 123
- `/storesmodel toggleFavourite <code>` - Favourite (or unfavourite) a store by its code

Methods that take tables (e.g. `BasketModel:add(items)`) can't be called this way — arguments are only numbers, booleans and strings. Use the controller action, or a method with simple arguments.

### Server-Scoped Models

Server-scoped models (in `ServerScriptService/models/server/`) operate on shared server state. There are none in this repo yet; one would be reached as `/<name>model <method> [args...]` and act on the single `"SERVER"` instance. (`UserSession` models such as `OwnershipModel` aren't registered for slash commands.)

### Controller Actions

Controller commands (in `ServerScriptService/controllers/`) trigger controller actions with full validation.

**Example - BasketController:**
- `/basketcontroller Clear` - Empty your basket (counts against the basket rate budget, like a real request)

**Example - AvatarController:**
- `/avatarcontroller Undo` - Undo your last avatar change
- `/avatarcontroller TakeOffAll` - Take off everything you're wearing

**Example - WorldOptionsController:**
- `/worldoptionscontroller Reset` - Reset your world options to defaults

## How It Works

### Automatic Discovery

When the server starts:

1. **ModelRunner** discovers all models under `ServerScriptService/models/`
2. **ControllerRunner** discovers all controllers in `ServerScriptService/controllers/`
3. **SlashCommandService** registers each discovered model and controller
4. **TextChatCommands** are created for autocomplete in chat

When the client starts:

1. **SlashCommandClient** waits for TextChatCommands to be created
2. Listens for command triggers from TextChatService
3. Sends commands to server via RemoteEvent

### Command Execution Flow

**For Model Commands:**

1. **Client**: TextChatService detects the command
2. **Client**: SlashCommandClient sends command string to server via Bolt ReliableEvent
3. **Server**: SlashCommandService validates your rank/permissions
4. **Server**: Parses command into model name, method name, and arguments
5. **Server**: Gets the appropriate model instance (your user model or server model)
6. **Server**: Calls the method with parsed arguments
7. **Model**: Method executes, updates state, calls `syncState()` to sync to clients
8. **Client**: Your views update automatically via Bolt Observe() callbacks

**For Controller Commands:**

1. **Client**: TextChatService detects the command
2. **Client**: SlashCommandClient sends command string to server via Bolt ReliableEvent
3. **Server**: SlashCommandService validates your rank/permissions
4. **Server**: Parses command into controller name, action name, and arguments
5. **Server**: Fires the controller's Bolt event: `intentEvent:Fire(player, action, args...)`
6. **Controller**: OnServerEvent handler receives the event (same as if client sent it)
7. **Controller**: Validates request, gets models, executes action handler
8. **Model**: Updates state, calls `syncState()` to sync to clients
9. **Client**: Your views update automatically via Bolt Observe() callbacks

**Key Difference:** Controller commands reuse the controller's existing Bolt ReliableEvent and validation logic, ensuring the same behavior as normal gameplay actions.

### Argument Parsing

Arguments are automatically converted to appropriate types:

| Input | Parsed As | Example |
|-------|-----------|---------|
| `1` | `number` | `/outfitsmodel rename 1 Party` |
| `true` or `false` | `boolean` | `/somemodel setFlag true` |
| `text` | `string` | `/favouritesmodel toggle Asset:123` |

## Creating Slash-Command-Friendly Models

No special code is needed! Just create models following the normal MVC pattern:

```lua
-- ServerScriptService/models/user/BasketModel.luau

function BasketModel:clear(): ()
    if #self.items > 0 then
        self.items = {}
        self:syncState()  -- This syncs to client as normal
    end
end
```

That's it! The `/basketmodel clear` command is now automatically available.

### Best Practices

**✅ DO:**
- Create descriptive method names (they become command names)
- Use type annotations for parameters (helps with debugging)
- Follow normal model patterns with `syncState()` for state updates
- Use commands for testing and debugging during development

**❌ DON'T:**
- Don't use slash commands for normal gameplay (use Views + Controllers instead)
- Don't create commands that bypass important validation logic
- Don't expose dangerous methods that could break game state

## Customizing Slash Commands

### Changing Rank Requirement

Edit `SlashCommandService.luau` line 26:

```lua
local MIN_RANK = 200  -- Change to your desired rank
```

### Disabling for Specific Models

Slash commands work for ALL models by default. To prevent a model from being accessible via slash commands, you would need to add filtering logic to SlashCommandService or mark the model as private (currently not supported - all models are accessible).

### Group ID Detection

The group ID is automatically detected in `SlashCommandService:init()`:

```lua
if game.CreatorType == Enum.CreatorType.Group then
    groupId = game.CreatorId  -- Automatically uses the owning group
else
    -- Game owned by user - allow all players (useful for Studio testing)
end
```

This works automatically across all your games - no hardcoding needed!

## Debugging

### Command Feedback

All command results are displayed directly in the **chat window**, making it easy to see what happened:

**Successful commands:**
```
Executed basketmodel:clear
Executed basketcontroller:Clear
```

**Error messages:**
```
Model 'wrongname' not found
Method 'wrongmethod' not found in basketmodel
Invalid command format. Usage: /<command> <method> [args...]
```

**Help output:**
```
=== Available Slash Commands ===

USER MODELS (per-player state):
  /basketmodel
  /favouritesmodel
  ...

CONTROLLERS:
  /avatarcontroller
  /basketcontroller
  ...

Usage: /commands [command] - Show methods/actions for a command
```

### Console Logging

The slash command system also includes server-side logging for monitoring:

**Client Console:**
```
[SlashCommandClient] Found TextChatCommands with 2 commands
[SlashCommandClient] Registering listener for command: /basketmodel
[SlashCommandClient] Command triggered: /basketmodel with text: "/basketmodel clear"
[SlashCommandClient] Sending to server: "basketmodel clear"
[ChatMessageClient] initialized
```

**Server Console:**
```
[SlashCommandService] Game owned by group 12345678. Rank 200+ required.
[SlashCommand] SUCCESS - PlayerName: Executed basketmodel:clear
[SlashCommand] PlayerName used /commands basketmodel
```

### Common Issues

**"Unknown slash command"**
- The TextChatCommand wasn't created - check that SlashCommandService initialized
- Check server console for `[SlashCommandService] Total models registered: X`

**"Nothing happens when I type command"**
- Check client console for SlashCommandClient initialization
- Verify you're typing the command correctly: `/modelname methodname args`

**"Permission denied"**
- Check your rank in the group: must be 200+
- Server console will show your current rank when denied
- In Studio (user-owned place), all commands should work

**"Method not found"**
- Verify the method exists on the model class
- Check spelling - command is case-sensitive
- Method must be a public function on the model instance

## File Structure

```
Source/
├── ServerScriptService/
│   ├── models/
│   │   ├── user/           ← User-scoped models (commands operate on player data)
│   │   │   └── BasketModel.luau, FavouritesModel.luau, ...
│   │   ├── server/         ← Server-scoped models (commands operate on server data; none yet)
│   │   └── ModelRunner.server.luau  ← Registers models with SlashCommandService
│   ├── services/
│   │   └── framework/SlashCommandService.luau  ← Server-side command handler & help system
│   └── controllers/
│       ├── AbstractController.luau   ← Base class (commands call each controller's executeAction)
│       └── BasketController.luau     ← Example; actions listed in Network.luau
└── ReplicatedFirst/
    ├── SlashCommandClient.client.luau  ← Client-side command listener
    └── ChatMessageClient.client.luau   ← Displays command feedback in chat
```

## Summary

Slash commands provide a **zero-configuration admin tool system**:

1. ✅ **No setup required** - Just create models and controllers normally
2. ✅ **Automatic discovery** - Commands appear when models/controllers are registered
3. ✅ **Permission-controlled** - Only high-rank users can execute
4. ✅ **Type-safe** - Arguments auto-parsed to correct types
5. ✅ **MVC-compliant** - Uses normal state broadcast flow
6. ✅ **Controller support** - Reuses existing validation and Bolt ReliableEvents

Use them for testing, debugging, and admin actions - but remember that normal gameplay should use the full MVC pattern (Views → Controllers → Models) for proper validation and security!
