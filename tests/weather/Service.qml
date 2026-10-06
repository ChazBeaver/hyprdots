import QtQuick
import Quickshell
import "weather" as Weather
Scope {
  property string scenario: Quickshell.env("WEATHER_TEST_SCENARIO")
  Weather.WeatherService {
    id: service
    location: scenario === "auto" ? "" : "Fixture City"
    onBusyChanged: {
      if (!busy && ready && activeKey === requestKey) done.restart()
    }
  }
  Timer {
    interval: 60; running: scenario === "race" || scenario === "units" || scenario === "queued"
    onTriggered: {
      if (scenario === "race") service.location = "Second City"
      else if (scenario === "units") service.units = "metric"
      else { service.refresh(); service.refresh(); service.refresh() }
    }
  }
  Timer {
    id: done; interval: 200
    onTriggered: {
      if (service.busy || service.activeKey !== service.requestKey) return
      console.log("WEATHER_RESULT " + JSON.stringify({report:service.report,error:service.errorMessage,stale:service.stale}))
      Qt.quit()
    }
  }
  Timer { interval: 8000; running: true; onTriggered: { console.log("WEATHER_TIMEOUT"); Qt.quit() } }
}
