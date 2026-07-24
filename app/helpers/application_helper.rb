module ApplicationHelper
  def pill(text)
    content_tag(:span, text, class: "inline-block px-2 py-0.5 mr-1 mb-1 rounded-full bg-gray-100 text-gray-700 text-xs")
  end
end
