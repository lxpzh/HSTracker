class AppDelegate
  include CDQ

  Log = Motion::Log

  def applicationDidFinishLaunching(notification)
    cdq.setup

    show_splash_screen

    # init logs
    Log.level = :debug

    Log.addLogger DDTTYLogger.sharedInstance

    file_logger                                        = DDFileLogger.new
    file_logger.rollingFrequency                       = 60 * 60 * 12
    file_logger.logFileManager.maximumNumberOfLogFiles = 7
    Log.addLogger file_logger

    # load cards into database if needed
    DatabaseGenerator.init_database do
      @splash.window.orderOut(self)

      Hearthstone.instance.on(:app_running) do |is_running|
        Log.info "Hearthstone is running? #{is_running}"
      end

      NSApp.mainMenu = MainMenu.new.menu

      @player = PlayerTracker.new
      @player.showWindow(self)
      @player.window.orderFrontRegardless

      @opponent = OpponentTracker.new
      @opponent.showWindow(self)
      @opponent.window.orderFrontRegardless

      @card_count_player = CardCountHud.alloc.initWithPlayer :player
      @card_count_player.showWindow(self)
      @card_count_player.window.orderFrontRegardless

      @card_count_opponent = CardCountHud.alloc.initWithPlayer :opponent
      @card_count_opponent.showWindow(self)
      @card_count_opponent.window.orderFrontRegardless

      Hearthstone.instance.listen(@player, :player)
      Hearthstone.instance.listen(@card_count_player, :player)
      Hearthstone.instance.listen(@card_count_opponent, :opponent)
      Hearthstone.instance.listen(@opponent, :opponent)

      NSNotificationCenter.defaultCenter.observe 'deck_change' do |_|
        reload_deck_menu
      end

      if Hearthstone.instance.is_hearthstone_running?
        Hearthstone.instance.start
      end

      VersionChecker.check

      NSNotificationCenter.defaultCenter.observe 'AppleLanguages_changed' do |_|
        response = NSAlert.alert('Language change'._,
                                 :buttons     => ['OK'._, 'Cancel'._],
                                 :informative => 'You must restart HSTracker for the language change to take effect'._)
        if response == NSAlertFirstButtonReturn
          @app_will_restart = true

          NSApplication.sharedApplication.terminate(nil)
          exit(0)
        end
      end
    end
  end

  def show_splash_screen
    @splash = LoadingScreen.alloc.init
    @splash.showWindow(nil)
  end

  # preferences
  def preferences
    @preferences ||= begin
      MASPreferencesWindowController.alloc.initWithViewControllers(
          [
              GeneralPreferences.alloc.init,
              InterfacePreferences.alloc.init
          ],
          title: 'Preferences'._)
    end
  end

  def openPreferences(_)
    preferences.showWindow(nil)
  end

  # deck manager
  def deck_manager
    @deck_manager ||= begin
      manager                 = DeckManager.alloc.init
      manager.window.delegate = self
      manager
    end
  end

  def open_deck_manager(_)
    # change windows level
    @player.window.setLevel NSNormalWindowLevel
    @opponent.window.setLevel NSNormalWindowLevel

    deck_manager.showWindow(nil)
    deck_manager.player_view = @player
  end

  # nswindowdelegate
  def windowShouldClose(sender)
    deck_manager.check_is_saved_on_close
  end

  def windowWillClose(notification)
    # change windows level back
    @player.window.setLevel NSScreenSaverWindowLevel
    @opponent.window.setLevel NSScreenSaverWindowLevel
  end

  # lock / unlock windows
  def lock_windows(menu_item)
    Configuration.windows_locked ? menu_item.title = 'Lock Windows'._ : menu_item.title = 'Unlock Windows'._

    Configuration.windows_locked = !Configuration.windows_locked
  end

  # open a deck
  def open_deck(menu_item)
    deck = Deck.by_name(menu_item.title)
    @player.show_deck(deck.playable_cards, deck.name)
  end

  # reset the trackers
  def reset(_)
    @player.game_start
    @opponent.game_start
  end

  def reload_deck_menu
    deck_menu = NSApp.mainMenu.itemWithTitle 'Decks'._
    deck_menu.submenu.removeAllItems

    item = NSMenuItem.alloc.initWithTitle('Reset'._, action: 'reset:', keyEquivalent: 'r')
    deck_menu.submenu.addItem item
    deck_menu.submenu.addItem NSMenuItem.separatorItem

    Deck.all.sort_by(:name, :case_insensitive => true).each do |deck|
      item = NSMenuItem.alloc.initWithTitle(deck.name, action: 'open_deck:', keyEquivalent: '')
      deck_menu.submenu.addItem item
    end
  end

  # restart HSTracker
  def applicationWillTerminate(_)
    if @app_will_restart
      app_path = NSBundle.mainBundle.bundlePath
      task     = NSTask.new
      task.setLaunchPath '/usr/bin/open'
      task.setArguments [app_path]
      task.launch
    end
  end
end
