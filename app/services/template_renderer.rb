# app/services/template_renderer.rb
class TemplateRenderer
  def self.render(template, data)
    return '' if template.blank?
    
    # Simple template rendering with {{ variable }} syntax
    result = template.dup
    
    # Replace all variables in the template
    data.each do |key, value|
      # Handle both escaped and unescaped curly braces
      result.gsub!(/\\\{\\\{\s*#{key}\s*\\\}\\\}/, value.to_s) # Escaped: \{\{ key \}\}
      result.gsub!(/\{\{\s*#{key}\s*\}\}/, value.to_s)         # Normal: {{ key }}
    end
    
    # Handle conditional blocks with simple if/endif syntax
    result = process_conditionals(result, data)
    
    result
  end
  
  private
  
  def self.process_conditionals(template, data)
    # This is a simplified implementation
    # A real one would handle nested conditionals and else blocks
    
    result = template.dup
    
    # Match if blocks with both escaped and unescaped syntax
    
    # Handle escaped conditionals: \{% if variable %\} content \{% endif %\}
    result.gsub!(/\\\{%\s*if\s+(\w+)\s*%\\\}(.*?)\\\{%\s*endif\s*%\\\}/m) do |match|
      var_name = $1
      content = $2
      
      # Check if the variable exists and is truthy
      if data[var_name.to_sym].present? || data[var_name].present?
        content
      else
        ''
      end
    end
    
    # Handle normal conditionals: {% if variable %} content {% endif %}
    result.gsub!(/\{%\s*if\s+(\w+)\s*%\}(.*?)\{%\s*endif\s*%\}/m) do |match|
      var_name = $1
      content = $2
      
      # Check if the variable exists and is truthy
      if data[var_name.to_sym].present? || data[var_name].present?
        content
      else
        ''
      end
    end
    
    result
  end
end
